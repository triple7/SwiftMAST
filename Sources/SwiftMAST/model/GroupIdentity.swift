/// Internal identity used to collect products belonging to the same observation group.
///
/// `targetName` is populated when scanning the local cache, where multiple targets
/// can be processed together. API results are already scoped by a query and use
/// the empty default value.
struct GroupIdentity: Hashable {
    let targetName: String
    let mission: String
    let observationKey: String
    let instrument: String

    init(
        targetName: String = "",
        mission: String,
        observationKey: String,
        instrument: String
    ) {
        self.targetName = targetName
        self.mission = mission
        self.observationKey = observationKey
        self.instrument = instrument
    }
}
