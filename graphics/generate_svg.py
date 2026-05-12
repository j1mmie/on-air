import math
import sys

def generate_svg_with_circle(diameter=10, offset_x=0, offset_y=0):
    """
    Generate SVG with a grid of black circles and a red circle overlay.
    
    Args:
        diameter: Diameter of the red circle in grid units
        offset_x: Horizontal offset of circle center from grid center (in grid units)
        offset_y: Vertical offset of circle center from grid center (in grid units)
    """
    # SVG header
    svg_lines = [
        '<svg width="320" height="320" viewBox="0 0 320 320" xmlns="http://www.w3.org/2000/svg">'
    ]
    
    # Grid coordinates - circles are at positions: 10, 30, 50, ... 310
    # That's indices 0-15 with spacing of 20 pixels each
    # Coordinate = 10 + index * 20
    
    # Center of the grid (in grid coordinates)
    center_x = 7.5 + offset_x
    center_y = 7.5 + offset_y
    
    # Radius of the circle in grid units
    radius = diameter / 2.0
    
    # Find which grid points are within the circle
    red_circles = set()
    for i in range(16):
        for j in range(16):
            x_coord = 10 + i * 20
            y_coord = 10 + j * 20
            
            # Distance from center in grid coordinates
            dist = math.sqrt((i - center_x)**2 + (j - center_y)**2)
            if dist <= radius:
                red_circles.add((x_coord, y_coord))
    
    # Generate all circles
    for i in range(16):
        for j in range(16):
            x_coord = 10 + i * 20
            y_coord = 10 + j * 20
            
            if (x_coord, y_coord) in red_circles:
                color = "red"
            else:
                color = "black"
            
            svg_lines.append(f'<circle cx="{x_coord}" cy="{y_coord}" r="6" fill="{color}"/>')
    
    svg_lines.append('</svg>')
    
    return '\n'.join(svg_lines)

# Default diameter 10 if no args provided
diameter = 10
offset_x = 0
offset_y = 0

if len(sys.argv) > 1:
    diameter = float(sys.argv[1])
if len(sys.argv) > 2:
    offset_x = float(sys.argv[2])
if len(sys.argv) > 3:
    offset_y = float(sys.argv[3])

# Generate and write SVG
svg_content = generate_svg_with_circle(diameter, offset_x, offset_y)

with open(r'c:\Users\jimmie\Projects\on-air\graphics\icons\icon.svg', 'w') as f:
    f.write(svg_content)

print(f"Generated SVG with diameter {diameter}, offset ({offset_x}, {offset_y})")
