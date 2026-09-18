# MAST TAP Filtering and Ordering Benchmark

- Date: 2026-09-18
- Target: NGC 628
- Missions: JWST, HST, HLA
- Candidate limit: 100, balanced across missions
- Mission workers: 3
- Maximum product size: 70 MiB
- Maximum selected size: 500 MiB
- Maximum selected products: 20

## Question

Should fixed eligibility checks run in the TAP query or after rows arrive in
Python, and how does minimum/maximum file-size ordering affect performance and
selection quality?

The TAP-side checks were:

- non-null `s_region`, filter, instrument, content length, and download URI;
- positive content length;
- content length no greater than 70 MiB.

Dynamic marginal coverage, new-filter gain, grouping, and total-budget checks
always remained in the local greedy selector.

## Results

| Filter location | TAP order | Wall time | Rows | Eligible | Selected | Filters | Coverage | Selected MiB | Report KiB |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Local | Group | 21.94 s | 100 | 64 | 18 | 17 | 0.123060 | 476.99 | 243.3 |
| TAP | Group | 19.64 s | 87 | 72 | 20 | 20 | 0.088692 | 420.60 | 220.7 |
| Local | Minimum size | 20.69 s | 100 | 74 | 20 | 20 | 0.026608 | 197.44 | 246.2 |
| TAP | Minimum size | 28.80 s | 87 | 74 | 20 | 20 | 0.026608 | 197.44 | 221.9 |
| Local | Maximum size | 10.88 s* | 100 | 7 | 6 | 4 | 0.141907 | 315.73 | 260.1 |
| TAP | Maximum size | 15.01 s* | 87 | 66 | 18 | 18 | 0.177938 | 476.81 | 221.2 |

`Report KiB` is a convenient metadata-size proxy, not a measurement of FITS
download bytes or exact HTTP response bytes.

\* The maximum-size rows are bounded reruns using a 40-second timeout and no
retry. An earlier local-filter/maximum-size run exceeded 150 seconds and was
stopped. This demonstrates substantial MAST/server-cache variability and the
cost risk of descending content-length sorts.

## Findings

1. TAP filtering reduced returned/report metadata by approximately 9–15%.
2. TAP filtering did not guarantee a faster query. It was 10.5% faster for the
   group order, but 39.2% slower for minimum-size ordering in these samples.
3. Minimum-size ordering produced the smallest download plan (197.44 MiB) but
   very low spatial coverage (0.026608). Local and TAP filtering selected the
   exact same 20 products for this order.
4. Local maximum-size ordering wasted 93 of 100 rows on products over 70 MiB.
   Applying the size limit in TAP before `TOP` exposed 66 eligible candidates
   and improved coverage from 0.141907 to 0.177938.
5. Filtering before `TOP` can change the candidate frontier and therefore the
   final science result. It is not merely a runtime optimization.
6. Local preparation and greedy selection were sub-second. TAP execution and
   network/server variability dominated wall time.

## Recommendation

Use a hybrid policy:

- Push indisputable static rejection rules into TAP, especially null/zero
  content length, the configured per-product size ceiling, missing footprint,
  and missing retrieval URI.
- Repeat validation locally because archive strings can still be blank,
  malformed, pseudo-filters, or duplicates.
- Keep marginal coverage, filter diversity, total budget, and greedy scoring
  local because they change after each selection.
- Keep group ordering as the general default. Minimum-size ordering is useful
  for a download-minimization preset, while maximum-size ordering should remain
  experimental because file size is only a weak proxy for sky coverage and its
  database sort time was unstable.
- Over-fetch or use per-mission/per-instrument quotas when selection quality is
  more important than metadata volume; any `TOP` plus ordering combination can
  bias the candidate frontier.

One benchmark sample is sufficient to expose selection differences, but not to
claim stable MAST latency. For a performance decision, repeat each configuration
at different times and compare median and percentile timings.

## Maximum-size verification rerun

Because the initial maximum-content-length result was surprising, the local and
TAP-filtered variants were rerun three times with tighter controls:

- fixed RA/Dec, removing target-resolution time;
- 60-second TAP timeout;
- zero retries;
- alternating strategy order;
- otherwise identical target, missions, limits, workers, and budgets.

| Filter location | Run 1 | Run 2 | Run 3 | Completed | Median wall time |
|---|---:|---:|---:|---:|---:|
| Local | 8.62 s | 60.89 s timeout/partial | 12.31 s | 2/3 | 12.31 s including the timeout as the middle value |
| TAP | 12.15 s | 12.04 s | 12.40 s | 3/3 | 12.15 s |

Every complete local run returned 100 rows but only 7 eligible candidates; 93
were rejected for exceeding 70 MiB. Every TAP-filtered run returned 87 rows and
66 eligible candidates. The completed selections were deterministic within each
strategy:

| Filter location | Selected | Filters | Coverage |
|---|---:|---:|---:|
| Local | 6 | 4 | 0.141907 |
| TAP | 18 | 18 | 0.177938 |

This rerun does not show that TAP filtering makes every successful query much
faster: the successful medians were similar. It shows that applying the size
ceiling before descending `ORDER BY contentlength` avoids an unbounded sort that
can time out and prevents oversized products from consuming almost the entire
`TOP` window. TAP filtering was therefore more reliable and produced a much more
useful candidate frontier for maximum-size ordering.

## Controlled group-versus-maximum comparison

Group ordering was then repeated three times using the same fixed-coordinate,
60-second, zero-retry controls as the maximum-size verification.

| Strategy | Run 1 | Run 2 | Run 3 | Median | Completed |
|---|---:|---:|---:|---:|---:|
| Local / group | 9.20 s | 15.25 s | 8.39 s | 9.20 s | 3/3 |
| TAP / group | 15.68 s | 13.49 s | 12.42 s | 13.49 s | 3/3 |
| Local / maximum size | 8.62 s | 60.89 s partial | 12.31 s | 12.31 s | 2/3 |
| TAP / maximum size | 12.15 s | 12.04 s | 12.40 s | 12.15 s | 3/3 |

The completed strategy outputs were stable across repetitions:

| Strategy | Rows | Eligible | Selected | Filters | Coverage | Selected MiB |
|---|---:|---:|---:|---:|---:|---:|
| Local / group | 100 | 64 | 18 | 17 | 0.123060 | 476.99 |
| TAP / group | 87 | 72 | 20 | 20 | 0.088692 | 420.60 |
| Local / maximum size | 100 | 7 | 6 | 4 | 0.141907 | 315.73 |
| TAP / maximum size | 87 | 66 | 18 | 18 | 0.177938 | 476.81 |

For TAP-filtered queries, maximum-size ordering was approximately 10% faster by
median than group ordering in this controlled sample. It also doubled spatial
coverage (0.177938 versus 0.088692), but returned two fewer filters and consumed
approximately 56 MiB more of the selection budget. This is a candidate-frontier
effect, not an improvement to the greedy algorithm itself: `TOP` sees large files
first and the local selector cannot consider products outside that window.

Group ordering remains the safer general default because it exposes a broader
observation/filter structure and does not assume file size represents useful sky
area. TAP-filtered maximum-size ordering is a useful coverage-oriented preset for
this target, but it should be validated on several targets before becoming a
general policy.

## TAP record-limit probe

MAST's live [CAOM TAP capabilities document](https://mast.stsci.edu/vo-tap/api/v0.1/caom/capabilities)
declares both its default output limit and hard output limit as **100,000 rows**.
This is the service-side result ceiling; it does not mean every synchronous query
that requests 100,000 rows will finish before an HTTP gateway timeout.

Incremental synchronous queries used the application's full selected-column set,
fixed NGC 628 coordinates, the JWST/HST/HLA mission filters, and no retries. The
radius was widened when the target no longer had enough matching rows to exercise
the requested `TOP` value.

| Radius | Requested `TOP` | Returned rows | Wall time | Report size | Result |
|---:|---:|---:|---:|---:|---|
| 0.1 deg | 100 | 100 | 7.29 s | 0.158 MiB | Success |
| 0.1 deg | 250 | 250 | 7.23 s | 0.372 MiB | Success |
| 0.1 deg | 500 | 500 | 8.80 s | 0.744 MiB | Success |
| 0.1 deg | 1,000 | 722 | 7.90 s | 1.071 MiB | Success; only 722 matches |
| 1 deg | 1,000 | 969 | 18.28 s | 1.412 MiB | Success |
| 2 deg | 2,000 | 1,099 | 24.98 s | 1.628 MiB | Success |
| 3 deg | 2,000 | 1,311 | 24.93 s | 1.913 MiB | Success |
| 4 deg | 2,000 | 1,393 | 35.40 s | 2.023 MiB | Success |
| 5 deg | 5,000 | — | 66.19 s | — | HTTP 504 |

The largest successful application-shaped response in this probe was 1,393
rows, but that is **not** the TAP row limit. It is only the largest result tested
successfully for this target, query shape, and synchronous endpoint. The
5-degree request failed because the server or gateway did not finish the more
expensive spatial query in time.

For routine interactive use, keep the synchronous query bounded and partition
large searches by mission, instrument, time range, or sky region. Use TAP's
asynchronous execution path for expensive searches, then combine and deduplicate
the partitions locally before running the greedy selector. No single response can
exceed the advertised 100,000-row hard limit.
