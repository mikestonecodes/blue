package main

/*

This is the file where you actually make the game.

It will grow pretty phat. This is where the magic happens.

GAMEPLAY O'CLOCK !

*/

import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"

VERSION: string : "v0.0.0"
WINDOW_TITLE :: "Template [lib]"
GAME_RES_WIDTH :: 480
GAME_RES_HEIGHT :: 270
window_w := 1280
window_h := 720

ZLayer :: enum u8 {
	// Can add as many layers as you want in here.
	// Quads get sorted and drawn lowest to highest.
	// When things are on the same layer, they follow normal call order.
	nil,
	background,
	shadow,
	playspace,
	vfx,
	ui,
	tooltip,
	pause_menu,
	top,
}

Sprite_Name :: enum {
	nil,
	bald_logo,
	fmod_logo,
	player_still,
	shadow_medium,
	bg_repeat_tex0,
	player_death,
	player_run,
	player_idle,
	// to add new sprites, just put the .png in the res/images folder
	// and add the name to the enum here
	//
	// we could auto-gen this based on all the .png's in the images folder
	// but I don't really see the point right now. It's not hard to type lol.
}

sprite_data: [Sprite_Name]Sprite_Data = #partial {
	.player_idle = {frame_count=2},
	.player_run = {frame_count=3}
}



//
// epic game state

Game_State :: struct {
	ticks:             u64,
	game_time_elapsed: f64,
	cam_pos:           Vec2, // this is used by the renderer

	// entity system
	entity_top_count:  int,
	latest_entity_id:  int,
	entities:          [MAX_ENTITIES]Entity,
	entity_free_list:  [dynamic]int,

	// sloppy state dump
	player_handle:     Entity_Handle,
	scratch:           struct {
		all_entities: []Entity_Handle,
	},
}

//
// action -> key mapping


Input_Action :: enum u8 {
	left,
	right,
	up,
	down,
	click,
	use,
	interact,
}

action_map: map[Input_Action]Key_Code

//
// entity system

Entity :: struct {
	handle:              Entity_Handle,
	kind:                Entity_Kind,

	// todo, move this into static entity data
	update_proc:         proc(_: ^Entity),
	draw_proc:           proc(_: Entity),

	// big sloppy entity state dump.
	// add whatever you need in here.
	pos:                 Vec2,
	last_known_x_dir:    f32,
	flip_x:              bool,
	draw_offset:         Vec2,
	draw_pivot:          Pivot,
	rotation:            f32,
	hit_flash:           Vec4,
	sprite:              Sprite_Name,
	anim_index:          int,
	next_frame_end_time: f64,
	loop:                bool,
	frame_duration:      f32,

	// this gets zeroed every frame. Useful for passing data to other systems.
	scratch:             struct {
		col_override: Vec4,
	},
}

Entity_Kind :: enum {
	nil,
	player,
	thing1,
}

entity_setup :: proc(e: ^Entity, kind: Entity_Kind) {
	// entity defaults
	e.draw_proc = draw_entity_default
	e.draw_pivot = .bottom_center

	switch kind {
	case .nil:
	case .player:
		setup_player(e)
	case .thing1:
		setup_thing1(e)
	}
}

//
// main game procs

app_init :: proc() {
	action_map[.left] = .A
	action_map[.right] = .D
	action_map[.up] = .W
	action_map[.down] = .S
	action_map[.click] = .LEFT_MOUSE
	action_map[.use] = .RIGHT_MOUSE
	action_map[.interact] = .E
}

app_frame :: proc() {

	// right now we are just calling the game update, but in future this is where you'd do a big
	// "UX" switch for startup splash, main menu, settings, in-game, etc

	{
		// ui space example
		push_coord_space(get_screen_space())

		x, y := screen_pivot(.top_left)
		x += 2
		y -= 2
		draw_text({x, y}, "hello world.", z_layer = .ui, pivot = Pivot.top_left)
	}


	game_update()
	game_draw()

	volume: f32 = 0.75
}

app_shutdown :: proc() {
	// called on exit
}

game_update :: proc() {
	ctx.gs.scratch = {} // auto-zero scratch for each update
	defer {
		// update at the end
		ctx.gs.game_time_elapsed += f64(ctx.delta_t)
		ctx.gs.ticks += 1
	}

	// this'll be using the last frame's camera position, but it's fine for most things
	push_coord_space(get_world_space())

	// setup world for first game tick
	if ctx.gs.ticks == 0 {
		player := entity_create(.player)
		ctx.gs.player_handle = player.handle
	}

	rebuild_scratch_helpers()

	// big :update time
	for handle in get_all_ents() {
		e := entity_from_handle(handle)

		update_entity_animation(e)

		if e.update_proc != nil {
			e.update_proc(e)
		}
	}

	if key_pressed(.LEFT_MOUSE) {
		consume_key_pressed(.LEFT_MOUSE)

		pos := mouse_pos_in_current_space()
		log.info("schloop at", pos)
	}

	animate_to_target_v2(&ctx.gs.cam_pos, get_player().pos, ctx.delta_t, rate = 10)

	// ... add whatever other systems you need here to make epic game
}

rebuild_scratch_helpers :: proc() {
	// construct the list of all entities on the temp allocator
	// that way it's easier to loop over later on
	all_ents := make(
		[dynamic]Entity_Handle,
		0,
		len(ctx.gs.entities),
		allocator = context.temp_allocator,
	)
	for &e in ctx.gs.entities {
		if !is_valid(e) do continue
		append(&all_ents, e.handle)
	}
	ctx.gs.scratch.all_entities = all_ents[:]
}

game_draw :: proc() {

	// this is so we can get the current pixel in the shader in world space (VERYYY useful)
	draw_frame.ndc_to_world_xform =
		get_world_space_camera() * linalg.inverse(get_world_space_proj())
	draw_frame.bg_repeat_tex0_atlas_uv = atlas_uv_from_sprite(.bg_repeat_tex0)

	// background thing
	{
		// identity matrices, so we're in clip space
		push_coord_space({proj = Matrix4(1), camera = Matrix4(1)})

		// draw rect that covers the whole screen
		draw_rect(Rect{-1, -1, 1, 1}, flags = .background_pixels) // we leave it in the hands of the shader
	}

	// world
	{
		push_coord_space(get_world_space())

		draw_sprite({10, 10}, .player_still, col_override = Vec4{1, 0, 0, 0.4})
		draw_sprite({-10, 10}, .player_still)

		draw_text({0, -50}, "sugon", pivot = .bottom_center, col = {0, 0, 0, 0.1})

		for handle in get_all_ents() {
			e := entity_from_handle(handle)
			e.draw_proc(e^)
		}
	}
}

// note, this needs to be in the game layer because it varies from game to game.
// Specifically, stuff like anim_index and whatnot aren't guarenteed to be named the same or actually even be on the base entity.
// (in terrafactor, it's inside a sub state struct)
draw_entity_default :: proc(e: Entity) {
	e := e // need this bc we can't take a reference from a procedure parameter directly

	if e.sprite == nil {
		return
	}

	xform := xform_rotate(e.rotation)

	draw_sprite_entity(
		&e,
		e.pos,
		e.sprite,
		xform = xform,
		anim_index = e.anim_index,
		draw_offset = e.draw_offset,
		flip_x = e.flip_x,
		pivot = e.draw_pivot,
	)
}

// helper for drawing a sprite that's based on an entity.
// useful for systems-based draw overrides, like having the concept of a hit_flash across all entities
draw_sprite_entity :: proc(
	entity: ^Entity,
	pos: Vec2,
	sprite: Sprite_Name,
	pivot := Pivot.center_center,
	flip_x := false,
	draw_offset := Vec2{},
	xform := Matrix4(1),
	anim_index := 0,
	col := WHITE,
	col_override: Vec4 = {},
	z_layer: ZLayer = {},
	flags: Quad_Flags = {},
	params: Vec4 = {},
	crop_top: f32 = 0.0,
	crop_left: f32 = 0.0,
	crop_bottom: f32 = 0.0,
	crop_right: f32 = 0.0,
	z_layer_queue := -1,
) {

	col_override := col_override

	col_override = entity.scratch.col_override
	if entity.hit_flash.a != 0 {
		col_override.xyz = entity.hit_flash.xyz
		col_override.a = max(col_override.a, entity.hit_flash.a)
	}

	draw_sprite(
		pos,
		sprite,
		pivot,
		flip_x,
		draw_offset,
		xform,
		anim_index,
		col,
		col_override,
		z_layer,
		flags,
		params,
		crop_top,
		crop_left,
		crop_bottom,
		crop_right,
	)
}

//
// ~ Gameplay Slop Waterline ~
//
// From here on out, it's gameplay slop time.
// Structure beyond this point just slows things down.
//
// No point trying to make things 'reusable' for future projects.
// It's trivially easy to just copy and paste when needed.
//

// shorthand for getting the player
get_player :: proc() -> ^Entity {
	return entity_from_handle(ctx.gs.player_handle)
}

setup_player :: proc(e: ^Entity) {
	e.kind = .player

	// this offset is to take it from the bottom center of the aseprite document
	// and center it at the feet
	e.draw_offset = Vec2{0.5, 5}
	e.draw_pivot = .bottom_center

	e.update_proc = proc(e: ^Entity) {

		input_dir := get_input_vector()
		e.pos += input_dir * 100.0 * ctx.delta_t

		if input_dir.x != 0 {
			e.last_known_x_dir = input_dir.x
		}

		e.flip_x = e.last_known_x_dir < 0

		if input_dir == {} {
			entity_set_animation(e, .player_idle, 0.3)
		} else {
			entity_set_animation(e, .player_run, 0.1)
		}

		e.scratch.col_override = Vec4{0, 0, 1, 0.2}
	}

	e.draw_proc = proc(e: Entity) {
		draw_sprite(e.pos, .shadow_medium, col = {1, 1, 1, 0.2})
		draw_entity_default(e)
	}
}

setup_thing1 :: proc(using e: ^Entity) {
	kind = .thing1
}

entity_set_animation :: proc(
	e: ^Entity,
	sprite: Sprite_Name,
	frame_duration: f32,
	looping := true,
) {
	if e.sprite != sprite {
		e.sprite = sprite
		e.loop = looping
		e.frame_duration = frame_duration
		e.anim_index = 0
		e.next_frame_end_time = 0
	}
}
update_entity_animation :: proc(e: ^Entity) {
	if e.frame_duration == 0 do return

	frame_count := get_frame_count(e.sprite)

	is_playing := true
	if !e.loop {
		is_playing = e.anim_index + 1 <= frame_count
	}

	if is_playing {

		if e.next_frame_end_time == 0 {
			e.next_frame_end_time = now() + f64(e.frame_duration)
		}

		if end_time_up(e.next_frame_end_time) {
			e.anim_index += 1
			e.next_frame_end_time = 0
			//e.did_frame_advance = true
			if e.anim_index >= frame_count {

				if e.loop {
					e.anim_index = 0
				}

			}
		}
	}
}
