package main

import tt "vendor:stb/truetype"

draw_text :: draw_text_with_drop_shadow

draw_text_wrapped :: proc(
	pos: Vec2,
	text: string,
	wrap_width: f32,
	col := WHITE,
	scale := 1.0,
	pivot := Pivot.bottom_left,
	z_layer := ZLayer.nil,
	col_override := Vec4{0, 0, 0, 0},
) -> Vec2 {
	// TODO
	return draw_text_no_drop_shadow(pos, text, col, scale, pivot, z_layer, col_override)
}

draw_text_with_drop_shadow :: proc(
	pos: Vec2,
	text: string,
	drop_shadow_col := BLACK,
	col := WHITE,
	scale := 1.0,
	pivot := Pivot.bottom_left,
	z_layer := ZLayer.nil,
	col_override := Vec4{0, 0, 0, 0},
) -> Vec2 {

	offset := Vec2{1, -1} * f32(scale)
	draw_text_no_drop_shadow(
		pos + offset,
		text,
		col = drop_shadow_col * col,
		scale = scale,
		pivot = pivot,
		z_layer = z_layer,
		col_override = col_override,
	)
	dim := draw_text_no_drop_shadow(
		pos,
		text,
		col = col,
		scale = scale,
		pivot = pivot,
		z_layer = z_layer,
		col_override = col_override,
	)

	return dim
}

draw_text_no_drop_shadow :: proc(
	pos: Vec2,
	text: string,
	col := WHITE,
	scale := 1.0,
	pivot := Pivot.bottom_left,
	z_layer := ZLayer.nil,
	col_override := Vec4{0, 0, 0, 0},
) -> (
	text_bounds: Vec2,
) {
	using tt

	push_z_layer(z_layer != .nil ? z_layer : draw_frame.active_z_layer)

	// loop thru and find the text size box thingo
	total_size: Vec2
	for char, i in text {

		advance_x: f32
		advance_y: f32
		q: aligned_quad
		GetBakedQuad(
			&font.char_data[0],
			font_bitmap_w,
			font_bitmap_h,
			cast(i32)char - 32,
			&advance_x,
			&advance_y,
			&q,
			false,
		)
		// this is the the data for the aligned_quad we're given, with y+ going down
		// x0, y0,     s0, t0, // top-left
		// x1, y1,     s1, t1, // bottom-right

		size := Vec2{abs(q.x0 - q.x1), abs(q.y0 - q.y1)}

		bottom_left := Vec2{q.x0, -q.y1}
		top_right := Vec2{q.x1, -q.y0}
		assert(bottom_left + size == top_right)

		if i == len(text) - 1 {
			total_size.x += size.x
		} else {
			total_size.x += advance_x
		}

		total_size.y = max(total_size.y, top_right.y)
	}

	pivot_offset := total_size * -scale_from_pivot(pivot)

	debug_text := false
	if debug_text {
		draw_rect(rect_make(pos + pivot_offset, total_size), col = BLACK)
	}

	// draw glyphs one by one
	x: f32
	y: f32
	for char in text {

		advance_x: f32
		advance_y: f32
		q: aligned_quad
		GetBakedQuad(
			&font.char_data[0],
			font_bitmap_w,
			font_bitmap_h,
			cast(i32)char - 32,
			&advance_x,
			&advance_y,
			&q,
			false,
		)
		// this is the the data for the aligned_quad we're given, with y+ going down
		// x0, y0,     s0, t0, // top-left
		// x1, y1,     s1, t1, // bottom-right

		size := Vec2{abs(q.x0 - q.x1), abs(q.y0 - q.y1)}

		bottom_left := Vec2{q.x0, -q.y1}
		top_right := Vec2{q.x1, -q.y0}
		assert(bottom_left + size == top_right)

		offset_to_render_at := Vec2{x, y} + bottom_left

		offset_to_render_at += pivot_offset

		uv := Vec4{q.s0, q.t1, q.s1, q.t0}

		xform := Matrix4(1)
		xform *= xform_translate(pos)
		xform *= xform_scale(Vec2{auto_cast scale, auto_cast scale})
		xform *= xform_translate(offset_to_render_at)

		if debug_text {
			draw_rect_xform(xform, size, col = Vec4{1, 1, 1, 0.8})
		}

		draw_rect_xform(
			xform,
			size,
			uv = uv,
			tex_index = 1,
			col_override = col_override,
			col = col,
		)

		x += advance_x
		y += -advance_y
	}

	return total_size * f32(scale)
}
