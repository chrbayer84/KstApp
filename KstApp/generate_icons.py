#!/usr/bin/env python3
"""
Generate KST app icons in various sizes
Uses only built-in Python libraries
"""

import os

def create_icon(size):
    """Create an icon of the specified size"""
    # Create a new image with black background
    img = Image.new('RGBA', (size, size), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    
    # Calculate scaling factor
    scale = size / 1024.0
    
    # Draw rounded rectangle background
    corner_radius = int(180 * scale)
    draw.rounded_rectangle([0, 0, size, size], radius=corner_radius, fill=(0, 0, 0, 255))
    
    # Green color for speech bubbles
    green = (0, 200, 81, 255)  # #00C851
    
    # First speech bubble (left, incoming)
    bubble1_x = int(200 * scale)
    bubble1_y = int(300 * scale)
    bubble1_w = int(280 * scale)
    bubble1_h = int(200 * scale)
    bubble1_r = int(20 * scale)
    
    draw.rounded_rectangle([bubble1_x, bubble1_y, bubble1_x + bubble1_w, bubble1_y + bubble1_h], 
                          radius=bubble1_r, fill=green)
    
    # Speech bubble tail
    tail_points = [
        (bubble1_x, bubble1_y + int(100 * scale)),
        (bubble1_x - int(50 * scale), bubble1_y + int(150 * scale)),
        (bubble1_x, bubble1_y + int(200 * scale))
    ]
    draw.polygon(tail_points, fill=green)
    
    # Second speech bubble (right, outgoing)
    bubble2_x = int(544 * scale)
    bubble2_y = int(200 * scale)
    bubble2_w = int(280 * scale)
    bubble2_h = int(200 * scale)
    bubble2_r = int(20 * scale)
    
    draw.rounded_rectangle([bubble2_x, bubble2_y, bubble2_x + bubble2_w, bubble2_y + bubble2_h], 
                          radius=bubble2_r, fill=green)
    
    # Speech bubble tail (right side)
    tail2_points = [
        (bubble2_x + bubble2_w, bubble2_y + int(100 * scale)),
        (bubble2_x + bubble2_w + int(50 * scale), bubble2_y + int(50 * scale)),
        (bubble2_x + bubble2_w, bubble2_y)
    ]
    draw.polygon(tail2_points, fill=green)
    
    # Third speech bubble (left, smaller)
    bubble3_x = int(150 * scale)
    bubble3_y = int(600 * scale)
    bubble3_w = int(200 * scale)
    bubble3_h = int(150 * scale)
    bubble3_r = int(15 * scale)
    
    draw.rounded_rectangle([bubble3_x, bubble3_y, bubble3_x + bubble3_w, bubble3_y + bubble3_h], 
                          radius=bubble3_r, fill=green)
    
    # Speech bubble tail
    tail3_points = [
        (bubble3_x, bubble3_y + int(75 * scale)),
        (bubble3_x - int(50 * scale), bubble3_y + int(125 * scale)),
        (bubble3_x, bubble3_y + int(175 * scale))
    ]
    draw.polygon(tail3_points, fill=green)
    
    # KST Text overlay
    try:
        # Try to use a bold font
        font_size = int(180 * scale)
        font = ImageFont.truetype("/System/Library/Fonts/Arial.ttf", font_size)
    except:
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
        except:
            font = ImageFont.load_default()
    
    text = "KST"
    text_bbox = draw.textbbox((0, 0), text, font=font)
    text_width = text_bbox[2] - text_bbox[0]
    text_height = text_bbox[3] - text_bbox[1]
    
    text_x = (size - text_width) // 2
    text_y = (size - text_height) // 2 + int(50 * scale)  # Slightly below center
    
    draw.text((text_x, text_y), text, fill=(255, 255, 255, 255), font=font)
    
    return img

def main():
    """Generate all required icon sizes"""
    sizes = [
        (40, "icon-20@2x.png"),      # 20pt @2x
        (60, "icon-20@3x.png"),      # 20pt @3x
        (58, "icon-29@2x.png"),      # 29pt @2x
        (87, "icon-29@3x.png"),      # 29pt @3x
        (80, "icon-40@2x.png"),      # 40pt @2x
        (120, "icon-40@3x.png"),     # 40pt @3x
        (120, "icon-60@2x.png"),     # 60pt @2x
        (180, "icon-60@3x.png"),     # 60pt @3x
        (1024, "icon-1024.png")      # App Store
    ]
    
    output_dir = "Assets.xcassets/AppIcon.appiconset"
    os.makedirs(output_dir, exist_ok=True)
    
    for size, filename in sizes:
        print(f"Generating {filename} ({size}x{size})...")
        img = create_icon(size)
        img.save(os.path.join(output_dir, filename), "PNG")
        print(f"Saved {filename}")

if __name__ == "__main__":
    main()
