package game

import rl "vendor:raylib"
import "core:path/filepath"
import "core:strings"
import "core:fmt"
import "core:c/libc"
import "core:strconv"
import "core:mem"

PIXEL_WINDOW_HEIGHT :: 180
CHECKERBOARD_SIZE :: 20.0 // Size of each checkerboard square
MASK_BRUSH_SIZE :: 20.0 // Default brush size for masking
ZOOM_SENSITIVITY :: 0.1 // How much zoom changes per scroll unit

Game_Memory :: struct {
	run: bool,
	loaded_texture: rl.Texture2D,
	has_image: bool,
	image_path: string, // Store the path of the dropped image
	max_colors: i32, // Max colors for palette generation
	max_colors_input: [16]u8, // Text input buffer for max_colors
	max_colors_input_len: i32, // Current length of input
	max_colors_focused: bool, // Whether the text box is focused
	// Checkboxes
	dither_enabled: bool,
	color_correct_enabled: bool,
	apply_palette_enabled: bool,
	dither_scale: i32, // Dither scale (1-5)
	dither_scale_input: [16]u8, // Text input buffer for dither scale
	dither_scale_input_len: i32,
	dither_scale_focused: bool,
	// Zoom and pan
	image_zoom: f32, // Current zoom level (1.0 = fit to screen)
	image_pan_x: f32, // Pan offset X
	image_pan_y: f32, // Pan offset Y
	base_scale: f32, // Base scale when image is first loaded
	// Masking
	mask_active: bool, // Whether masking mode is active
	mask_texture: rl.RenderTexture2D, // Render texture for mask
	mask_brush_size: f32, // Brush size for masking
	panning: bool, // Whether currently panning
	last_pan_x: f32, // Last pan mouse position X
	last_pan_y: f32, // Last pan mouse position Y
}

g: ^Game_Memory

update :: proc() {
	if rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}

	// Handle file dropping
	if rl.IsFileDropped() {
		dropped_files := rl.LoadDroppedFiles()
		
		if dropped_files.count > 0 {
			file_path := dropped_files.paths[0]

			if g.image_path != "" {
				delete(g.image_path)
			}
			g.image_path = strings.clone(string(file_path))
			
			// Load the image
			image := rl.LoadImage(file_path)
			if image.data != nil {
				if g.has_image {
					rl.UnloadTexture(g.loaded_texture)
				}
				
				// Convert image to texture
				g.loaded_texture = rl.LoadTextureFromImage(image)
				g.has_image = true
				
				g.image_zoom = 1.0
				g.image_pan_x = 0.0
				g.image_pan_y = 0.0
				
				// Calculate base scale
				screen_width := f32(rl.GetScreenWidth())
				screen_height := f32(rl.GetScreenHeight())
				tex_width := f32(image.width)
				tex_height := f32(image.height)
				scale_x := screen_width / tex_width
				scale_y := screen_height / tex_height
				g.base_scale = min(scale_x, scale_y) * 0.9
				
				// Initialize mask texture
				if g.mask_texture.id != 0 {
					rl.UnloadRenderTexture(g.mask_texture)
				}
				g.mask_texture = rl.LoadRenderTexture(i32(image.width), i32(image.height))
				rl.BeginTextureMode(g.mask_texture)
				rl.ClearBackground(rl.Color{0, 0, 0, 0}) // Transparent
				rl.EndTextureMode()
				g.mask_active = false
				g.mask_brush_size = MASK_BRUSH_SIZE
				
				// Unload the image (we only need the texture)
				rl.UnloadImage(image)
			}
		}
		
		rl.UnloadDroppedFiles(dropped_files)
	}

	handle_text_input()
	handle_checkbox_clicks()
	handle_dither_scale_input()
	handle_zoom_pan()
	handle_masking()
	handle_brush_size_adjustment()
}

handle_brush_size_adjustment :: proc() {
	if !g.mask_active {
		return
	}
	
	// Increase brush size with ]
	if rl.IsKeyPressed(.RIGHT_BRACKET) {
		g.mask_brush_size = min(100.0, g.mask_brush_size + 5.0)
		fmt.printf("Brush size: %.0f\n", g.mask_brush_size)
	}
	
	// Decrease brush size with [
	if rl.IsKeyPressed(.LEFT_BRACKET) {
		g.mask_brush_size = max(5.0, g.mask_brush_size - 5.0)
		fmt.printf("Brush size: %.0f\n", g.mask_brush_size)
	}
}

// Button rectangle and state
BUTTON_WIDTH :: 200.0
BUTTON_HEIGHT :: 50.0
BUTTON_PADDING :: 20.0
INPUT_BOX_WIDTH :: 120.0
INPUT_BOX_HEIGHT :: 30.0
CHECKBOX_SIZE :: 20.0
CHECKBOX_SPACING :: 30.0
APPLY_BUTTON_WIDTH :: 150.0
APPLY_BUTTON_HEIGHT :: 40.0
DITHER_SCALE_INPUT_WIDTH :: 40.0
DITHER_SCALE_INPUT_HEIGHT :: 24.0

get_button_rect :: proc() -> rl.Rectangle {
	screen_width := f32(rl.GetScreenWidth())
	return {
		x = screen_width - BUTTON_WIDTH - BUTTON_PADDING,
		y = BUTTON_PADDING,
		width = BUTTON_WIDTH,
		height = BUTTON_HEIGHT,
	}
}

get_input_box_rect :: proc() -> rl.Rectangle {
	screen_width := f32(rl.GetScreenWidth())
	return {
		x = screen_width - BUTTON_WIDTH - BUTTON_PADDING,
		y = BUTTON_PADDING + BUTTON_HEIGHT + 10 + 20,
		width = INPUT_BOX_WIDTH,
		height = INPUT_BOX_HEIGHT,
	}
}

handle_text_input :: proc() {
	input_box_rect := get_input_box_rect()
	mouse_pos := rl.GetMousePosition()
	
	// Check if clicking on input box
	if rl.IsMouseButtonPressed(.LEFT) {
		if rl.CheckCollisionPointRec(mouse_pos, input_box_rect) {
			g.max_colors_focused = true
		} else {
			g.max_colors_focused = false
		}
	}
	
	if !g.max_colors_focused {
		return
	}
	
	// Handle keyboard input
	key := rl.GetCharPressed()
	if key != 0 {
		if g.max_colors_input_len < i32(len(g.max_colors_input)) - 1 {
			// Only allow digits
			if key >= '0' && key <= '9' {
				g.max_colors_input[g.max_colors_input_len] = u8(key)
				g.max_colors_input_len += 1
				
				update_max_colors_from_input()
			}
		}
	}
	
	// Handle backspace
	if rl.IsKeyPressed(.BACKSPACE) && g.max_colors_input_len > 0 {
		g.max_colors_input_len -= 1
		g.max_colors_input[g.max_colors_input_len] = 0
		update_max_colors_from_input()
	}
}

update_max_colors_from_input :: proc() {
	if g.max_colors_input_len > 0 {
		input_str := string(g.max_colors_input[:g.max_colors_input_len])
		if value, ok := strconv.parse_int(input_str); ok {
			if value > 0 && value <= 256 {
				g.max_colors = i32(value)
			}
		}
	}
}

get_checkbox_rect :: proc(y_offset: f32) -> rl.Rectangle {
	screen_width := f32(rl.GetScreenWidth())
	return {
		x = screen_width - BUTTON_WIDTH - BUTTON_PADDING,
		y = y_offset,
		width = CHECKBOX_SIZE,
		height = CHECKBOX_SIZE,
	}
}

get_dither_scale_input_rect :: proc(checkbox_x: f32, checkbox_y: f32) -> rl.Rectangle {
	// Position after "Dither" label + "Scale:" label
	dither_label_width := f32(rl.MeasureText(strings.clone_to_cstring("Dither", context.temp_allocator), 16))
	scale_label_width := f32(rl.MeasureText(strings.clone_to_cstring("Scale:", context.temp_allocator), 16))
	start_x := checkbox_x + CHECKBOX_SIZE + 8 + dither_label_width + 10 + scale_label_width + 5
	return {
		x = start_x,
		y = checkbox_y,
		width = DITHER_SCALE_INPUT_WIDTH,
		height = DITHER_SCALE_INPUT_HEIGHT,
	}
}

get_apply_button_rect :: proc(y_offset: f32) -> rl.Rectangle {
	screen_width := f32(rl.GetScreenWidth())
	return {
		x = screen_width - BUTTON_WIDTH - BUTTON_PADDING,
		y = y_offset,
		width = APPLY_BUTTON_WIDTH,
		height = APPLY_BUTTON_HEIGHT,
	}
}

handle_checkbox_clicks :: proc() {
	mouse_pos := rl.GetMousePosition()
	
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	
	if !g.has_image || g.image_path == "" {
		return
	}
	
	// Calculate starting Y position for checkboxes (below the max colors input)
	start_y := f32(BUTTON_PADDING + BUTTON_HEIGHT + 10 + 20 + INPUT_BOX_HEIGHT + 20)
	
	// Dither checkbox
	dither_checkbox := get_checkbox_rect(start_y)
	if rl.CheckCollisionPointRec(mouse_pos, dither_checkbox) {
		g.dither_enabled = !g.dither_enabled
	}
	
	// Color correct checkbox
	color_correct_checkbox := get_checkbox_rect(start_y + CHECKBOX_SPACING)
	if rl.CheckCollisionPointRec(mouse_pos, color_correct_checkbox) {
		g.color_correct_enabled = !g.color_correct_enabled
	}
	
	// Apply palette checkbox
	apply_palette_checkbox := get_checkbox_rect(start_y + CHECKBOX_SPACING * 2)
	if rl.CheckCollisionPointRec(mouse_pos, apply_palette_checkbox) {
		g.apply_palette_enabled = !g.apply_palette_enabled
	}
	
	// Apply button
	apply_button_y := start_y + CHECKBOX_SPACING * 3 + 10
	apply_button := get_apply_button_rect(apply_button_y)
	if rl.CheckCollisionPointRec(mouse_pos, apply_button) {
		apply_effects()
	}
	
	// Create Palette button (moved after Apply button)
	create_palette_button_y := apply_button_y + APPLY_BUTTON_HEIGHT + 10
	create_palette_button := get_button_rect()
	create_palette_button.y = create_palette_button_y
	if rl.CheckCollisionPointRec(mouse_pos, create_palette_button) {
		create_palette_no_args()
	}
	
	// Add Mask button
	add_mask_button_y := create_palette_button_y + BUTTON_HEIGHT + 10
	add_mask_button := get_button_rect()
	add_mask_button.y = add_mask_button_y
	if rl.CheckCollisionPointRec(mouse_pos, add_mask_button) {
		g.mask_active = !g.mask_active
		if !g.mask_active {
			// Clear mask when deactivating
			clear_mask()
		}
	}
	
	// Clear Mask button (only if masking is active)
	if g.mask_active {
		clear_mask_button_y := add_mask_button_y + BUTTON_HEIGHT + 10
		clear_mask_button := get_button_rect()
		clear_mask_button.y = clear_mask_button_y
		if rl.CheckCollisionPointRec(mouse_pos, clear_mask_button) {
			clear_mask()
		}
		
		// Export Masked Area button
		export_mask_button_y := clear_mask_button_y + BUTTON_HEIGHT + 10
		export_mask_button := get_button_rect()
		export_mask_button.y = export_mask_button_y
		if rl.CheckCollisionPointRec(mouse_pos, export_mask_button) {
			export_masked_area()
		}
	}
}

handle_dither_scale_input :: proc() {
	if !g.dither_enabled {
		g.dither_scale_focused = false
		return
	}
	
	start_y := f32(BUTTON_PADDING + BUTTON_HEIGHT + 10 + 20 + INPUT_BOX_HEIGHT + 20)
	dither_checkbox := get_checkbox_rect(start_y)
	dither_scale_input_rect := get_dither_scale_input_rect(dither_checkbox.x, dither_checkbox.y)
	mouse_pos := rl.GetMousePosition()
	
	// Check if clicking on input box
	if rl.IsMouseButtonPressed(.LEFT) {
		if rl.CheckCollisionPointRec(mouse_pos, dither_scale_input_rect) {
			g.dither_scale_focused = true
		} else {
			g.dither_scale_focused = false
		}
	}
	
	if !g.dither_scale_focused {
		return
	}
	
	// Handle keyboard input
	key := rl.GetCharPressed()
	if key != 0 {
		if g.dither_scale_input_len < 2 {
			if key >= '0' && key <= '9' {
				g.dither_scale_input[g.dither_scale_input_len] = u8(key)
				g.dither_scale_input_len += 1
				update_dither_scale_from_input()
			}
		}
	}
	
	// Handle backspace
	if rl.IsKeyPressed(.BACKSPACE) && g.dither_scale_input_len > 0 {
		g.dither_scale_input_len -= 1
		g.dither_scale_input[g.dither_scale_input_len] = 0
		update_dither_scale_from_input()
	}
}

update_dither_scale_from_input :: proc() {
	if g.dither_scale_input_len > 0 {
		input_str := string(g.dither_scale_input[:g.dither_scale_input_len])
		if value, ok := strconv.parse_int(input_str); ok {
			if value >= 1 && value <= 5 {
				g.dither_scale = i32(value)
			}
		}
	}
}

get_image_rect :: proc() -> (rect: rl.Rectangle, scale: f32) {
	if !g.has_image {
		return {}, 0.0
	}
	
	screen_width := f32(rl.GetScreenWidth())
	screen_height := f32(rl.GetScreenHeight())
	tex_width := f32(g.loaded_texture.width)
	tex_height := f32(g.loaded_texture.height)
	
	scale = g.base_scale * g.image_zoom
	scaled_width := tex_width * scale
	scaled_height := tex_height * scale
	
	// Center the image with pan offset
	x := (screen_width - scaled_width) / 2.0 + g.image_pan_x
	y := (screen_height - scaled_height) / 2.0 + g.image_pan_y
	
	return rl.Rectangle{x = x, y = y, width = scaled_width, height = scaled_height}, scale
}

screen_to_image_coords :: proc(screen_x: f32, screen_y: f32) -> (img_x: f32, img_y: f32, is_inside: bool) {
	if !g.has_image {
		return 0.0, 0.0, false
	}
	
	image_rect, scale := get_image_rect()
	
	if !rl.CheckCollisionPointRec({screen_x, screen_y}, image_rect) {
		return 0.0, 0.0, false
	}
	
	// Convert screen coordinates to image coordinates
	img_x = (screen_x - image_rect.x) / scale
	img_y = (screen_y - image_rect.y) / scale
	
	is_inside = img_x >= 0 && img_x < f32(g.loaded_texture.width) && img_y >= 0 && img_y < f32(g.loaded_texture.height)
	return
}

handle_zoom_pan :: proc() {
	if !g.has_image {
		return
	}
	
	mouse_pos := rl.GetMousePosition()
	
	// Handle zoom with scroll wheel
	scroll := rl.GetMouseWheelMove()
	if scroll != 0 {
		// Zoom towards mouse position
		old_zoom := g.image_zoom
		new_zoom := max(0.1, min(10.0, g.image_zoom + scroll * ZOOM_SENSITIVITY))
		
		// Calculate image position before zoom
		image_rect_before, _ := get_image_rect()
		
		// Set new zoom
		g.image_zoom = new_zoom
		
		// Adjust pan to zoom towards mouse
		zoom_factor := new_zoom / old_zoom
		g.image_pan_x += (mouse_pos.x - image_rect_before.x) * (1.0 - zoom_factor)
		g.image_pan_y += (mouse_pos.y - image_rect_before.y) * (1.0 - zoom_factor)
	}
	
	// Handle panning with middle mouse button
	if rl.IsMouseButtonPressed(.MIDDLE) {
		g.panning = true
		g.last_pan_x = mouse_pos.x
		g.last_pan_y = mouse_pos.y
	}
	
	if rl.IsMouseButtonDown(.MIDDLE) && g.panning {
		g.image_pan_x += mouse_pos.x - g.last_pan_x
		g.image_pan_y += mouse_pos.y - g.last_pan_y
		g.last_pan_x = mouse_pos.x
		g.last_pan_y = mouse_pos.y
	}
	
	if rl.IsMouseButtonReleased(.MIDDLE) {
		g.panning = false
	}
}

handle_masking :: proc() {
	if !g.has_image || !g.mask_active {
		return
	}
	
	// Don't paint if panning or clicking on UI
	if g.panning {
		return
	}
	
	mouse_pos := rl.GetMousePosition()
	
	// Don't paint if clicking on UI elements (check if mouse is over UI area)
	screen_width := f32(rl.GetScreenWidth())
	ui_x := screen_width - BUTTON_WIDTH - BUTTON_PADDING
	if mouse_pos.x >= ui_x {
		return
	}
	
	img_x, img_y, is_inside := screen_to_image_coords(mouse_pos.x, mouse_pos.y)
	
	if !is_inside {
		return
	}
	
	// Handle painting (left mouse button)
	if rl.IsMouseButtonDown(.LEFT) {
		paint_mask(img_x, img_y, true)
	}
	
	// Handle erasing (right mouse button)
	if rl.IsMouseButtonDown(.RIGHT) {
		paint_mask(img_x, img_y, false)
	}
}

paint_mask :: proc(img_x: f32, img_y: f32, paint: bool) {
	if g.mask_texture.id == 0 {
		return
	}
	
	mask_width := f32(g.mask_texture.texture.width)
	mask_height := f32(g.mask_texture.texture.height)
	
	// Clamp coordinates to texture bounds
	img_x_clamped := max(0.0, min(img_x, mask_width - 1))
	// Flip Y coordinate - RenderTextures have flipped Y coordinates in Raylib
	img_y_flipped := mask_height - img_y - 1
	img_y_clamped := max(0.0, min(img_y_flipped, mask_height - 1))
	
	// Convert brush size from screen space to image space
	_, scale := get_image_rect()
	brush_size_img := g.mask_brush_size / scale
	
	brush_size_img = max(1.0, brush_size_img)
	
	// Draw on mask texture
	rl.BeginTextureMode(g.mask_texture)
	
	if paint {
		// Paint black with 80% opacity
		color := rl.Color{0, 0, 0, 204} // 80% opacity = 204/255
		rl.DrawCircle(i32(img_x_clamped), i32(img_y_clamped), brush_size_img, color)
		rl.EndTextureMode()
	} else {
		// Erase: Load texture as image, clear pixels in circular area, then update texture
		rl.EndTextureMode()
		
		// Load mask texture as image
		mask_image := rl.LoadImageFromTexture(g.mask_texture.texture)
		if mask_image.data == nil {
			return
		}
		
		// Clear pixels in circular area by setting alpha to 0
		brush_radius_sq := brush_size_img * brush_size_img
		// Use original coordinates (not flipped) for pixel access
		// Image data is stored with Y=0 at top, not flipped like RenderTexture
		center_x := i32(img_x_clamped)
		center_y_normal := i32(max(0.0, min(img_y, mask_height - 1))) // Use original img_y, not flipped
		
		// Calculate bounding box for efficiency
		min_x := max(0, center_x - i32(brush_size_img) - 1)
		max_x := min(i32(mask_width), center_x + i32(brush_size_img) + 1)
		min_y := max(0, center_y_normal - i32(brush_size_img) - 1)
		max_y := min(i32(mask_height), center_y_normal + i32(brush_size_img) + 1)
		
		// Access image data directly (flat array: y * width + x)
		// Create a slice from the raw pointer
		total_pixels := i32(mask_width * mask_height)
		pixels := mem.slice_ptr(cast(^rl.Color)mask_image.data, int(total_pixels))
		width := i32(mask_width)
		for y in min_y..<max_y {
			for x in min_x..<max_x {
				dx := f32(x) - img_x_clamped
				dy := f32(y) - f32(center_y_normal) // Use normal coordinate
				dist_sq := dx * dx + dy * dy
				
				if dist_sq <= brush_radius_sq {
					// Clear this pixel (set alpha to 0)
					index := y * width + x
					pixels[index].a = 0
				}
			}
		}
		
		// Update texture from modified image
		// Use UpdateTexture to update the existing texture data
		// This preserves the RenderTexture structure
		rl.UpdateTexture(g.mask_texture.texture, mask_image.data)
		rl.UnloadImage(mask_image)
	}
}

clear_mask :: proc() {
	if g.mask_texture.id == 0 {
		return
	}
	
	rl.BeginTextureMode(g.mask_texture)
	rl.ClearBackground(rl.Color{0, 0, 0, 0}) // Transparent
	rl.EndTextureMode()
	g.mask_active = false
}

// Export mask texture to PNG file
export_mask_texture :: proc(mask_path: string) -> bool {
	if g.mask_texture.id == 0 {
		return false
	}
	
	// Load image from the mask texture
	mask_image := rl.LoadImageFromTexture(g.mask_texture.texture)
	if mask_image.data == nil {
		return false
	}
	
	// Export image to PNG
	mask_path_cstring := strings.clone_to_cstring(mask_path, context.temp_allocator)
	success := rl.ExportImage(mask_image, mask_path_cstring)
	rl.UnloadImage(mask_image)
	
	return success
}

export_masked_area :: proc() {
	if g.image_path == "" || g.mask_texture.id == 0 {
		return
	}
	
	// Get base image name and directory
	base_name := filepath.stem(g.image_path)
	dir := filepath.dir(g.image_path)
	ext := filepath.ext(g.image_path)
	
	// Export mask texture to temporary file
	mask_path := fmt.tprintf("%s/%s_mask_temp.png", dir, base_name)
	if !export_mask_texture(mask_path) {
		fmt.printf("Error: Failed to export mask texture\n")
		return
	}
	
	// Export masked area - extract only the parts of the image that are under the mask
	// The mask is black where we painted. We want to extract those regions.
	// We'll use the mask's alpha channel to extract the masked regions.
	output_path := fmt.tprintf("%s/%s_masked_area%s", dir, base_name, ext)
	
	// Use ffmpeg to extract masked regions

	// Load the original image
	original_image := rl.LoadImage(strings.clone_to_cstring(g.image_path, context.temp_allocator))
	if original_image.data == nil {
		fmt.printf("Error: Failed to load original image\n")
		return
	}
	defer rl.UnloadImage(original_image)
	
	// Load the mask texture as an image
	mask_image := rl.LoadImageFromTexture(g.mask_texture.texture)
	if mask_image.data == nil {
		fmt.printf("Error: Failed to load mask texture\n")
		return
	}
	defer rl.UnloadImage(mask_image)
	
	// Create a new image for the masked area (same size as original)
	masked_image := rl.ImageCopy(original_image)
	
	// Get pixel data
	orig_width := original_image.width
	orig_height := original_image.height
	mask_width := mask_image.width
	mask_height := mask_image.height
	
	// Ensure dimensions match
	if orig_width != mask_width || orig_height != mask_height {
		fmt.printf("Error: Image and mask dimensions don't match\n")
		rl.UnloadImage(masked_image)
		return
	}
	
	// Access pixel data
	total_pixels := i32(orig_width * orig_height)
	orig_pixels := mem.slice_ptr(cast(^rl.Color)original_image.data, int(total_pixels))
	mask_pixels := mem.slice_ptr(cast(^rl.Color)mask_image.data, int(total_pixels))
	masked_pixels := mem.slice_ptr(cast(^rl.Color)masked_image.data, int(total_pixels))
	
	// Copy pixels where mask alpha > 0, make others transparent
	for i in 0..<int(total_pixels) {
		if mask_pixels[i].a > 0 {
			// Keep the original pixel
			masked_pixels[i] = orig_pixels[i]
		} else {
			// Make transparent
			masked_pixels[i] = rl.Color{0, 0, 0, 0}
		}
	}
	
	// Export the masked image
	output_path_cstring := strings.clone_to_cstring(output_path, context.temp_allocator)
	success := rl.ExportImage(masked_image, output_path_cstring)
	rl.UnloadImage(masked_image)
	
	if !success {
		fmt.printf("Error: Failed to export masked image\n")
		return
	}
	
	fmt.printf("Masked area exported to: %s\n", output_path)
	
	// Clean up intermediate file
	delete_file_if_exists(mask_path)
}

// Helper function to delete a file if it exists
delete_file_if_exists :: proc(file_path: string) {
	delete_cmd := fmt.tprintf("rm -f \"%s\"", file_path)
	result := libc.system(strings.clone_to_cstring(delete_cmd, context.temp_allocator))
	if result != 0 {
		fmt.printf("Warning: Failed to delete file %s: exit code %d\n", file_path, result)
	}
}

create_palette :: proc(input_path: string) {
	if input_path == "" {
		return
	}

	// Get base image name (without extension)
	base_name := filepath.stem(input_path)
	dir := filepath.dir(input_path)
	output_path := fmt.tprintf("%s/%s_palette.png", dir, base_name)

	command := fmt.tprintf("ffmpeg -y -i \"%s\" -vf \"palettegen=max_colors=%d:reserve_transparent=1\" \"%s\"", input_path, g.max_colors, output_path)
	
	result := libc.system(strings.clone_to_cstring(command, context.temp_allocator))
	if result != 0 {
		fmt.printf("Error running ffmpeg: exit code %d\n", result)
		return
	}
	
	fmt.printf("Palette created: %s\n", output_path)
}

// Helper function to create masked image if mask is active
// Returns the path to use (masked image path if mask was created, original path otherwise)
// This makes masked areas transparent - inverse of export_masked_area
create_masked_image_if_needed :: proc() -> (path: string, ok: bool) {
	if !g.mask_active || g.mask_texture.id == 0 {
		return g.image_path, true
	}
	
	// Get base image name and directory
	base_name := filepath.stem(g.image_path)
	dir := filepath.dir(g.image_path)
	ext := filepath.ext(g.image_path)
	masked_path := fmt.tprintf("%s/%s_masked%s", dir, base_name, ext)
	
	// Load the original image
	original_image := rl.LoadImage(strings.clone_to_cstring(g.image_path, context.temp_allocator))
	if original_image.data == nil {
		fmt.printf("Error: Failed to load original image\n")
		return g.image_path, false
	}
	defer rl.UnloadImage(original_image)
	
	// Load the mask texture as an image
	mask_image := rl.LoadImageFromTexture(g.mask_texture.texture)
	if mask_image.data == nil {
		fmt.printf("Error: Failed to load mask texture\n")
		return g.image_path, false
	}
	defer rl.UnloadImage(mask_image)
	
	// Create a new image for the masked result (same size as original)
	masked_image := rl.ImageCopy(original_image)
	
	// Get pixel data
	orig_width := original_image.width
	orig_height := original_image.height
	mask_width := mask_image.width
	mask_height := mask_image.height
	
	// Ensure dimensions match
	if orig_width != mask_width || orig_height != mask_height {
		fmt.printf("Error: Image and mask dimensions don't match\n")
		rl.UnloadImage(masked_image)
		return g.image_path, false
	}
	
	// Access pixel data
	total_pixels := i32(orig_width * orig_height)
	orig_pixels := mem.slice_ptr(cast(^rl.Color)original_image.data, int(total_pixels))
	mask_pixels := mem.slice_ptr(cast(^rl.Color)mask_image.data, int(total_pixels))
	masked_pixels := mem.slice_ptr(cast(^rl.Color)masked_image.data, int(total_pixels))
	
	// Copy pixels from original, but make masked areas transparent
	// If mask alpha > 0, it means we painted there, so make it transparent
	for i in 0..<int(total_pixels) {
		if mask_pixels[i].a > 0 {
			// This area is masked - make it transparent
			masked_pixels[i] = rl.Color{0, 0, 0, 0}
		} else {
			// Keep the original pixel
			masked_pixels[i] = orig_pixels[i]
		}
	}
	
	// Export the masked image
	output_path_cstring := strings.clone_to_cstring(masked_path, context.temp_allocator)
	success := rl.ExportImage(masked_image, output_path_cstring)
	rl.UnloadImage(masked_image)
	
	if !success {
		fmt.printf("Error: Failed to export masked image\n")
		return g.image_path, false
	}
	
	fmt.printf("Masked image created: %s\n", masked_path)
	return masked_path, true
}

create_palette_no_args :: proc() {
	if g.image_path == "" {
		return
	}
	
	// Get base image name and directory for palette naming
	base_name := filepath.stem(g.image_path)
	dir := filepath.dir(g.image_path)
	
	// If mask is active, create masked image first and use that for palette generation
	input_path := g.image_path
	used_masked_image := false
	masked_path := ""
	if g.mask_active && g.mask_texture.id != 0 {
		masked_path_temp, ok := create_masked_image_if_needed()
		if ok {
			input_path = masked_path_temp
			masked_path = masked_path_temp
			used_masked_image = true
		} else {
			fmt.printf("Warning: Failed to create masked image, using original image for palette\n")
		}
	}
	
	create_palette(input_path)
	
	// If we used a masked image, the palette was created as _masked_palette.png
	// Copy it to _palette.png so both exist
	if used_masked_image {
		masked_palette_path := fmt.tprintf("%s/%s_masked_palette.png", dir, base_name)
		palette_path := fmt.tprintf("%s/%s_palette.png", dir, base_name)
		
		// Copy the masked palette to the regular palette name
		copy_cmd := fmt.tprintf("cp \"%s\" \"%s\"", masked_palette_path, palette_path)
		result := libc.system(strings.clone_to_cstring(copy_cmd, context.temp_allocator))
		if result != 0 {
			fmt.printf("Warning: Failed to copy masked palette to palette: exit code %d\n", result)
		} else {
			fmt.printf("Palette also saved as: %s\n", palette_path)
		}
		
		// Clean up intermediate files
		delete_file_if_exists(masked_palette_path)
		delete_file_if_exists(masked_path)
	}
}

apply_effects :: proc() {
	if g.image_path == "" {
		return
	}
	
	// Get base image name and directory
	base_name := filepath.stem(g.image_path)
	dir := filepath.dir(g.image_path)
	ext := filepath.ext(g.image_path)
	
	// If mask is active, create masked image first (masked areas become transparent)
	input_image_path, mask_created_successfully := create_masked_image_if_needed()
	if !mask_created_successfully {
		fmt.printf("Warning: Failed to create masked image, proceeding with original image\n")
		input_image_path = g.image_path
	}
	
	// If "Apply palette" is checked, create the palette AFTER mask is applied
	// This ensures the palette is created from the masked image, not the original
	if g.apply_palette_enabled {
		create_palette(input_image_path)
	}
	
	// Build palette path (should be in same directory as input)
	// Use the same base name logic as create_palette to ensure we reference the correct palette file
	// If mask was created, input_image_path will be the masked image, so palette will be named accordingly
	palette_base_name := filepath.stem(input_image_path)
	palette_path := fmt.tprintf("%s/%s_palette.png", dir, palette_base_name)
	
	// Build output path
	output_path := fmt.tprintf("%s/%s_post_effects%s", dir, base_name, ext)
	
	// Build filter_complex string conditionally
	filters := make([dynamic]string, context.temp_allocator)
	
	if g.color_correct_enabled {
		append(&filters, "eq=saturation=0.9:contrast=1.1")
	}
	
	if g.apply_palette_enabled {
		if g.dither_enabled {
			dither_filter := fmt.tprintf("paletteuse=dither=bayer:bayer_scale=%d", g.dither_scale)
			append(&filters, dither_filter)
		} else {
			append(&filters, "paletteuse")
		}
	}
	
	command: string
	
	if len(filters) == 0 {
		// No filters, just copy
		command = fmt.tprintf("ffmpeg -y -i \"%s\" \"%s\"", input_image_path, output_path)
	} else {
		// Join filters with commas
		filter_complex := ""
		for filter, i in filters {
			if i > 0 {
				filter_complex = fmt.tprintf("%s,", filter_complex)
			}
			filter_complex = fmt.tprintf("%s%s", filter_complex, filter)
		}
		
		if g.apply_palette_enabled {
			// Need palette input
			command = fmt.tprintf("ffmpeg -y -i \"%s\" -i \"%s\" -filter_complex \"%s\" \"%s\"", input_image_path, palette_path, filter_complex, output_path)
		} else {
			// No palette input needed
			command = fmt.tprintf("ffmpeg -y -i \"%s\" -filter_complex \"%s\" \"%s\"", input_image_path, filter_complex, output_path)
		}
	}
	
	result := libc.system(strings.clone_to_cstring(command, context.temp_allocator))
	if result != 0 {
		fmt.printf("Error running ffmpeg: exit code %d\n", result)
		return
	}
	
	fmt.printf("Effects applied: %s\n", output_path)
	
	// Clean up intermediate files if mask was used
	if mask_created_successfully {
		mask_temp_path := fmt.tprintf("%s/%s_mask_temp.png", dir, base_name)
		delete_file_if_exists(mask_temp_path)
		
		// Delete the masked image file
		masked_image_path := fmt.tprintf("%s/%s_masked%s", dir, base_name, ext)
		delete_file_if_exists(masked_image_path)

		if g.apply_palette_enabled {
			masked_palette_path := fmt.tprintf("%s/%s_masked_palette.png", dir, base_name)
			delete_file_if_exists(masked_palette_path)
		}
	}
}

draw_checkerboard :: proc(rect: rl.Rectangle) {
	light_gray := rl.Color{192, 192, 192, 255} // Light gray
	dark_gray := rl.Color{128, 128, 128, 255}  // Dark gray
	
	// Enable scissor mode to clip to the rectangle
	rl.BeginScissorMode(i32(rect.x), i32(rect.y), i32(rect.width), i32(rect.height))
	
	// Calculate the range to draw (extend beyond bounds to ensure coverage)
	start_x := i32(rect.x)
	start_y := i32(rect.y)
	end_x := i32(rect.x + rect.width)
	end_y := i32(rect.y + rect.height)
	
	// Round down to checkerboard boundaries
	aligned_start_x := (start_x / i32(CHECKERBOARD_SIZE)) * i32(CHECKERBOARD_SIZE)
	aligned_start_y := (start_y / i32(CHECKERBOARD_SIZE)) * i32(CHECKERBOARD_SIZE)
	
	// Draw one square past the end to ensure full coverage
	aligned_end_x := ((end_x + i32(CHECKERBOARD_SIZE) - 1) / i32(CHECKERBOARD_SIZE)) * i32(CHECKERBOARD_SIZE)
	aligned_end_y := ((end_y + i32(CHECKERBOARD_SIZE) - 1) / i32(CHECKERBOARD_SIZE)) * i32(CHECKERBOARD_SIZE)
	
	y := aligned_start_y
	for y < aligned_end_y {
		x := aligned_start_x
		row_parity := ((y - aligned_start_y) / i32(CHECKERBOARD_SIZE)) % 2
		
		for x < aligned_end_x {
			col_parity := ((x - aligned_start_x) / i32(CHECKERBOARD_SIZE)) % 2
			color := light_gray if ((row_parity + col_parity) % 2 == 0) else dark_gray
			
			// Always draw full-size squares - scissor will clip them
			rl.DrawRectangle(x, y, i32(CHECKERBOARD_SIZE), i32(CHECKERBOARD_SIZE), color)
			
			x += i32(CHECKERBOARD_SIZE)
		}
		y += i32(CHECKERBOARD_SIZE)
	}
	
	rl.EndScissorMode()
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	// Draw the loaded image if available
	if g.has_image {
		texture := g.loaded_texture
		image_rect, scale := get_image_rect()
		
		// Draw checkerboard pattern behind the image (for transparency)
		draw_checkerboard(image_rect)
		
		// Draw the image
		rl.DrawTextureEx(texture, {image_rect.x, image_rect.y}, 0.0, scale, rl.WHITE)
		
		// Draw mask overlay if active
		if g.mask_active && g.mask_texture.id != 0 {
			// Scale mask texture to match image size
			mask_tex := g.mask_texture.texture
			rl.DrawTextureEx(mask_tex, {image_rect.x, image_rect.y}, 0.0, scale, rl.WHITE)
		}
		
		// Draw brush cursor when masking
		if g.mask_active {
			mouse_pos := rl.GetMousePosition()
			_, _, is_inside := screen_to_image_coords(mouse_pos.x, mouse_pos.y)
			if is_inside {
				brush_size_screen := g.mask_brush_size
				rl.DrawCircleLines(i32(mouse_pos.x), i32(mouse_pos.y), brush_size_screen, rl.WHITE)
			}
		}
	} else {
		// Show hint text when no image is loaded
		hint_text := strings.clone_to_cstring("Drag and drop an image file here", context.temp_allocator)
		rl.DrawText(hint_text, 10, 10, 20, rl.GRAY)
	}

	// Draw UI elements
	if g.has_image {
		mouse_pos := rl.GetMousePosition()
		
		// Draw max colors input box
		input_box_rect := get_input_box_rect()
		input_hovered := rl.CheckCollisionPointRec(mouse_pos, input_box_rect)
		
		// Draw label
		label_text := "Max Colors:"
		label_cstring := strings.clone_to_cstring(label_text, context.temp_allocator)
		rl.DrawText(label_cstring, i32(input_box_rect.x), i32(input_box_rect.y - 20), 16, rl.WHITE)
		
		// Draw input box background
		input_color := rl.DARKGRAY if (g.max_colors_focused || input_hovered) else rl.GRAY
		rl.DrawRectangleRounded(input_box_rect, 0.2, 4, input_color)
		
		// Draw input box border
		border_color := rl.WHITE if g.max_colors_focused else rl.LIGHTGRAY
		rl.DrawRectangleRoundedLines(input_box_rect, 0.2, 4, border_color)
		
		// Draw input text
		if g.max_colors_input_len > 0 {
			input_text := string(g.max_colors_input[:g.max_colors_input_len])
			input_text_cstring := strings.clone_to_cstring(input_text, context.temp_allocator)
			rl.DrawText(input_text_cstring, i32(input_box_rect.x + 8), i32(input_box_rect.y + (input_box_rect.height - 16) / 2), 16, rl.WHITE)
		}
		
		// Draw cursor when focused
		if g.max_colors_focused {
			cursor_x := input_box_rect.x + 8
			if g.max_colors_input_len > 0 {
				input_text := string(g.max_colors_input[:g.max_colors_input_len])
				input_text_cstring := strings.clone_to_cstring(input_text, context.temp_allocator)
				cursor_x += f32(rl.MeasureText(input_text_cstring, 16))
			}
			// Blinking cursor (simple time-based)
			cursor_time := rl.GetTime()
			if i32(cursor_time * 2) % 2 == 0 {
				rl.DrawLine(i32(cursor_x), i32(input_box_rect.y + 5), i32(cursor_x), i32(input_box_rect.y + input_box_rect.height - 5), rl.WHITE)
			}
		}
		
		// Draw checkboxes and Apply button
		start_y := f32(BUTTON_PADDING + BUTTON_HEIGHT + 10 + 20 + INPUT_BOX_HEIGHT + 20)
		
		// Dither checkbox
		dither_checkbox := get_checkbox_rect(start_y)
		rl.DrawRectangleLinesEx(dither_checkbox, 2, rl.WHITE)
		if g.dither_enabled {
			check_color := rl.GREEN
			rl.DrawRectangleLinesEx({dither_checkbox.x + 4, dither_checkbox.y + 4, dither_checkbox.width - 8, dither_checkbox.height - 8}, 2, check_color)
			// Draw X or checkmark
			rl.DrawLine(i32(dither_checkbox.x + 4), i32(dither_checkbox.y + 4), i32(dither_checkbox.x + dither_checkbox.width - 4), i32(dither_checkbox.y + dither_checkbox.height - 4), check_color)
			rl.DrawLine(i32(dither_checkbox.x + dither_checkbox.width - 4), i32(dither_checkbox.y + 4), i32(dither_checkbox.x + 4), i32(dither_checkbox.y + dither_checkbox.height - 4), check_color)
		}
		dither_label_text := "Dither"
		dither_label_cstring := strings.clone_to_cstring(dither_label_text, context.temp_allocator)
		dither_label_x := dither_checkbox.x + CHECKBOX_SIZE + 8
		rl.DrawText(dither_label_cstring, i32(dither_label_x), i32(dither_checkbox.y + 2), 16, rl.WHITE)
		
		// Dither scale input (only if dither is checked) - inline with checkbox
		if g.dither_enabled {
			dither_scale_input_rect := get_dither_scale_input_rect(dither_checkbox.x, dither_checkbox.y)
			dither_scale_hovered := rl.CheckCollisionPointRec(mouse_pos, dither_scale_input_rect)
			
			// Draw "Scale:" label inline
			scale_label_text := "Scale:"
			scale_label_cstring := strings.clone_to_cstring(scale_label_text, context.temp_allocator)
			dither_label_width := f32(rl.MeasureText(dither_label_cstring, 16))
			scale_label_x := dither_label_x + dither_label_width + 10
			rl.DrawText(scale_label_cstring, i32(scale_label_x), i32(dither_checkbox.y + 2), 16, rl.WHITE)
			
			// Draw input box
			scale_input_color := rl.DARKGRAY if (g.dither_scale_focused || dither_scale_hovered) else rl.GRAY
			rl.DrawRectangleRounded(dither_scale_input_rect, 0.2, 4, scale_input_color)
			
			scale_border_color := rl.WHITE if g.dither_scale_focused else rl.LIGHTGRAY
			rl.DrawRectangleRoundedLines(dither_scale_input_rect, 0.2, 4, scale_border_color)
			
			// Draw input text
			if g.dither_scale_input_len > 0 {
				scale_input_text := string(g.dither_scale_input[:g.dither_scale_input_len])
				scale_input_text_cstring := strings.clone_to_cstring(scale_input_text, context.temp_allocator)
				rl.DrawText(scale_input_text_cstring, i32(dither_scale_input_rect.x + 6), i32(dither_scale_input_rect.y + (dither_scale_input_rect.height - 14) / 2), 14, rl.WHITE)
			}
			
			// Draw cursor when focused
			if g.dither_scale_focused {
				scale_cursor_x := dither_scale_input_rect.x + 6
				if g.dither_scale_input_len > 0 {
					scale_input_text := string(g.dither_scale_input[:g.dither_scale_input_len])
					scale_input_text_cstring := strings.clone_to_cstring(scale_input_text, context.temp_allocator)
					scale_cursor_x += f32(rl.MeasureText(scale_input_text_cstring, 14))
				}
				cursor_time := rl.GetTime()
				if i32(cursor_time * 2) % 2 == 0 {
					rl.DrawLine(i32(scale_cursor_x), i32(dither_scale_input_rect.y + 3), i32(scale_cursor_x), i32(dither_scale_input_rect.y + dither_scale_input_rect.height - 3), rl.WHITE)
				}
			}
		}
		
		// Color correct checkbox
		color_correct_checkbox := get_checkbox_rect(start_y + CHECKBOX_SPACING)
		rl.DrawRectangleLinesEx(color_correct_checkbox, 2, rl.WHITE)
		if g.color_correct_enabled {
			check_color := rl.GREEN
			rl.DrawRectangleLinesEx({color_correct_checkbox.x + 4, color_correct_checkbox.y + 4, color_correct_checkbox.width - 8, color_correct_checkbox.height - 8}, 2, check_color)
			rl.DrawLine(i32(color_correct_checkbox.x + 4), i32(color_correct_checkbox.y + 4), i32(color_correct_checkbox.x + color_correct_checkbox.width - 4), i32(color_correct_checkbox.y + color_correct_checkbox.height - 4), check_color)
			rl.DrawLine(i32(color_correct_checkbox.x + color_correct_checkbox.width - 4), i32(color_correct_checkbox.y + 4), i32(color_correct_checkbox.x + 4), i32(color_correct_checkbox.y + color_correct_checkbox.height - 4), check_color)
		}
		color_correct_label_text := "Color Correct"
		color_correct_label_cstring := strings.clone_to_cstring(color_correct_label_text, context.temp_allocator)
		rl.DrawText(color_correct_label_cstring, i32(color_correct_checkbox.x + CHECKBOX_SIZE + 8), i32(color_correct_checkbox.y + 2), 16, rl.WHITE)
		
		// Apply palette checkbox
		apply_palette_checkbox := get_checkbox_rect(start_y + CHECKBOX_SPACING * 2)
		rl.DrawRectangleLinesEx(apply_palette_checkbox, 2, rl.WHITE)
		if g.apply_palette_enabled {
			check_color := rl.GREEN
			rl.DrawRectangleLinesEx({apply_palette_checkbox.x + 4, apply_palette_checkbox.y + 4, apply_palette_checkbox.width - 8, apply_palette_checkbox.height - 8}, 2, check_color)
			rl.DrawLine(i32(apply_palette_checkbox.x + 4), i32(apply_palette_checkbox.y + 4), i32(apply_palette_checkbox.x + apply_palette_checkbox.width - 4), i32(apply_palette_checkbox.y + apply_palette_checkbox.height - 4), check_color)
			rl.DrawLine(i32(apply_palette_checkbox.x + apply_palette_checkbox.width - 4), i32(apply_palette_checkbox.y + 4), i32(apply_palette_checkbox.x + 4), i32(apply_palette_checkbox.y + apply_palette_checkbox.height - 4), check_color)
		}
		apply_palette_label_text := "Apply palette"
		apply_palette_label_cstring := strings.clone_to_cstring(apply_palette_label_text, context.temp_allocator)
		rl.DrawText(apply_palette_label_cstring, i32(apply_palette_checkbox.x + CHECKBOX_SIZE + 8), i32(apply_palette_checkbox.y + 2), 16, rl.WHITE)
		
		// Apply button
		apply_button_y := start_y + CHECKBOX_SPACING * 3 + 10
		apply_button := get_apply_button_rect(apply_button_y)
		apply_hovered := rl.CheckCollisionPointRec(mouse_pos, apply_button)
		
		// Draw button background
		apply_button_color := rl.DARKGRAY if apply_hovered else rl.GRAY
		rl.DrawRectangleRounded(apply_button, 0.3, 8, apply_button_color)
		
		// Draw button border
		rl.DrawRectangleRoundedLines(apply_button, 0.3, 8, rl.WHITE)
		
		// Draw button text
		apply_text := "Apply"
		apply_text_cstring := strings.clone_to_cstring(apply_text, context.temp_allocator)
		apply_text_size := rl.MeasureText(apply_text_cstring, 18)
		apply_text_x := apply_button.x + (apply_button.width - f32(apply_text_size)) / 2.0
		apply_text_y := apply_button.y + (apply_button.height - 18) / 2.0
		rl.DrawText(apply_text_cstring, i32(apply_text_x), i32(apply_text_y), 18, rl.WHITE)
		
		// Create Palette button (moved after Apply button)
		create_palette_button_y := apply_button_y + APPLY_BUTTON_HEIGHT + 10
		create_palette_button := get_button_rect()
		create_palette_button.y = create_palette_button_y
		create_palette_hovered := rl.CheckCollisionPointRec(mouse_pos, create_palette_button)
		
		// Draw button background
		create_palette_button_color := rl.DARKGRAY if create_palette_hovered else rl.GRAY
		rl.DrawRectangleRounded(create_palette_button, 0.3, 8, create_palette_button_color)
		
		// Draw button border
		rl.DrawRectangleRoundedLines(create_palette_button, 0.3, 8, rl.WHITE)
		
		// Draw button text
		create_palette_text := "Export Palette"
		create_palette_text_cstring := strings.clone_to_cstring(create_palette_text, context.temp_allocator)
		create_palette_text_size := rl.MeasureText(create_palette_text_cstring, 20)
		create_palette_text_x := create_palette_button.x + (create_palette_button.width - f32(create_palette_text_size)) / 2.0
		create_palette_text_y := create_palette_button.y + (create_palette_button.height - 20) / 2.0
		rl.DrawText(create_palette_text_cstring, i32(create_palette_text_x), i32(create_palette_text_y), 20, rl.WHITE)
		
		// Add Mask button
		add_mask_button_y := create_palette_button_y + BUTTON_HEIGHT + 10
		add_mask_button := get_button_rect()
		add_mask_button.y = add_mask_button_y
		add_mask_hovered := rl.CheckCollisionPointRec(mouse_pos, add_mask_button)
		
		// Draw button background
		add_mask_button_color := rl.DARKGRAY if add_mask_hovered else (rl.GREEN if g.mask_active else rl.GRAY)
		rl.DrawRectangleRounded(add_mask_button, 0.3, 8, add_mask_button_color)
		
		// Draw button border
		rl.DrawRectangleRoundedLines(add_mask_button, 0.3, 8, rl.WHITE)
		
		// Draw button text
		add_mask_text := "Add Mask"
		add_mask_text_cstring := strings.clone_to_cstring(add_mask_text, context.temp_allocator)
		add_mask_text_size := rl.MeasureText(add_mask_text_cstring, 20)
		add_mask_text_x := add_mask_button.x + (add_mask_button.width - f32(add_mask_text_size)) / 2.0
		add_mask_text_y := add_mask_button.y + (add_mask_button.height - 20) / 2.0
		rl.DrawText(add_mask_text_cstring, i32(add_mask_text_x), i32(add_mask_text_y), 20, rl.WHITE)
		
		// Show additional mask buttons if masking is active
		if g.mask_active {
			// Clear Mask button
			clear_mask_button_y := add_mask_button_y + BUTTON_HEIGHT + 10
			clear_mask_button := get_button_rect()
			clear_mask_button.y = clear_mask_button_y
			clear_mask_hovered := rl.CheckCollisionPointRec(mouse_pos, clear_mask_button)
			
			rl.DrawRectangleRounded(clear_mask_button, 0.3, 8, rl.DARKGRAY if clear_mask_hovered else rl.GRAY)
			rl.DrawRectangleRoundedLines(clear_mask_button, 0.3, 8, rl.WHITE)
			
			clear_mask_text := "Clear Mask"
			clear_mask_text_cstring := strings.clone_to_cstring(clear_mask_text, context.temp_allocator)
			clear_mask_text_size := rl.MeasureText(clear_mask_text_cstring, 20)
			clear_mask_text_x := clear_mask_button.x + (clear_mask_button.width - f32(clear_mask_text_size)) / 2.0
			clear_mask_text_y := clear_mask_button.y + (clear_mask_button.height - 20) / 2.0
			rl.DrawText(clear_mask_text_cstring, i32(clear_mask_text_x), i32(clear_mask_text_y), 20, rl.WHITE)
			
			// Export Masked Area button
			export_mask_button_y := clear_mask_button_y + BUTTON_HEIGHT + 10
			export_mask_button := get_button_rect()
			export_mask_button.y = export_mask_button_y
			export_mask_hovered := rl.CheckCollisionPointRec(mouse_pos, export_mask_button)
			
			rl.DrawRectangleRounded(export_mask_button, 0.3, 8, rl.DARKGRAY if export_mask_hovered else rl.GRAY)
			rl.DrawRectangleRoundedLines(export_mask_button, 0.3, 8, rl.WHITE)
			
			export_mask_text := "Export Masked Area"
			export_mask_text_cstring := strings.clone_to_cstring(export_mask_text, context.temp_allocator)
			export_mask_text_size := rl.MeasureText(export_mask_text_cstring, 18)
			export_mask_text_x := export_mask_button.x + (export_mask_button.width - f32(export_mask_text_size)) / 2.0
			export_mask_text_y := export_mask_button.y + (export_mask_button.height - 18) / 2.0
			rl.DrawText(export_mask_text_cstring, i32(export_mask_text_x), i32(export_mask_text_y), 18, rl.WHITE)
		}
	}

	rl.EndDrawing()
}

@(export)
game_update :: proc() {
	update()
	draw()

	// Everything on tracking allocator is valid until end-of-frame.
	free_all(context.temp_allocator)
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "Ditherpaletteizer")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(500)
	rl.SetExitKey(nil)
}

@(export)
game_init :: proc() {
	g = new(Game_Memory)

	g^ = Game_Memory {
		run = true,
		loaded_texture = {},
		has_image = false,
		image_path = "",
		max_colors = 32,
		max_colors_input = {},
		max_colors_input_len = 0,
		max_colors_focused = false,
		dither_enabled = true,
		color_correct_enabled = true,
		apply_palette_enabled = true,
		dither_scale = 5,
		dither_scale_input = {},
		dither_scale_input_len = 0,
		dither_scale_focused = false,
		image_zoom = 1.0,
		image_pan_x = 0.0,
		image_pan_y = 0.0,
		base_scale = 1.0,
		mask_active = false,
		mask_texture = {},
		mask_brush_size = MASK_BRUSH_SIZE,
		panning = false,
		last_pan_x = 0.0,
		last_pan_y = 0.0,
	}
	
	// Initialize input buffer with default value
	default_text := "32"
	for i := 0; i < len(default_text); i += 1 {
		g.max_colors_input[i] = default_text[i]
	}
	g.max_colors_input_len = i32(len(default_text))
	
	// Initialize dither scale input
	dither_default_text := "5"
	for i := 0; i < len(dither_default_text); i += 1 {
		g.dither_scale_input[i] = dither_default_text[i]
	}
	g.dither_scale_input_len = i32(len(dither_default_text))

	game_hot_reloaded(g)
}

@(export)
game_should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			return false
		}
	}

	return g.run
}

@(export)
game_shutdown :: proc() {
	// Clean up texture if loaded
	if g.has_image {
		rl.UnloadTexture(g.loaded_texture)
	}
	// Clean up mask texture
	if g.mask_texture.id != 0 {
		rl.UnloadRenderTexture(g.mask_texture)
	}
	// Clean up stored path
	if g.image_path != "" {
		delete(g.image_path)
	}
	free(g)
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return g
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = (^Game_Memory)(mem)

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside `g`.
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}
