from PIL import Image

def generate_split_image():
    # Define dimensions
    width, height = 500, 500
    
    # Create a new RGB image
    # 'L' mode could also be used for grayscale
    img = Image.new("RGB", (width, height))
    pixels = img.load()

    # Iterate through pixels
    for y in range(height):
        for x in range(width):
            if y < height // 2:
                # Top 50% - Black
                pixels[x, y] = (0, 0, 0)
            else:
                # Bottom 50% - White
                pixels[x, y] = (255, 255, 255)

    # Save the result
    img.save("half_black_half_white.png")
    print("Image saved as half_black_half_white.png")

if __name__ == "__main__":
    generate_split_image()