package main

/*

variable_main_loop_v1

This is the main entrypoint & structure of the frame / update loop.

This is an example of a simple variable timestep update & render, which I've found
to be a great sweet spot for small to medium sized singleplayer games.

Ideally, things are structured here in a way where you can just swap in a different main file
that does a different structure, like multiplayer, fixed timestep, etc, and it be kinda fine.
^ we'll see how this pans out

note:
It doesn't make sense to abstract this away into a package,
because it can vary depending on the game that's being made,
and is highly tangled with game state.

*/

import "base:builtin"
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:strings"
import "core:sync"
import "core:time"

import sapp "lib:sokol/app"
import sg "lib:sokol/gfx"
import gl "lib:sokol/gl"
import sglue "lib:sokol/glue"
import slog "lib:sokol/log"


Core_Context :: struct {
	gs:      ^Game_State,
	delta_t: f32,

	// #todo, put input in here and make helpers that wrap over
}
ctx: Core_Context

//
// MAIN

our_context: runtime.Context
main :: proc() {
	our_context = get_context_for_logging()
	context = our_context

	sapp.run(
		{
			init_cb = core_app_init,
			frame_cb = core_app_frame,
			cleanup_cb = core_app_shutdown,
			event_cb = event_callback,
			width = i32(window_w),
			height = i32(window_h),
			window_title = WINDOW_TITLE,
			icon = {sokol_default = true},
			logger = {func = slog.func},
		},
	)
}

// don't directly access this global, use the ctx.gs instead.
// (getting used to this will help later when you upgrade to a fixed timestep, don't worry about it now tho)
_actual_game_state: ^Game_State

core_app_init :: proc "c" () { 	// these sokol callbacks are c procs
	context = our_context // so we need to add the odin context in

	// we call the utility here so it can mark the start time of the program
	s := seconds_since_init()
	assert(s == 0)


	entity_init_core()

	_actual_game_state = new(Game_State)

	window_resize_callback = proc(width: int, height: int) {
		window_w = width
		window_h = height
	}

	render_init()

	app_init()
}

/*
note on "fixing your timestep": https://gafferongames.com/post/fix_your_timestep/

A fixed update timestep is only needed when it's needed. Not before.
It adds complexity. So there's no point taking on that complexity cost unless you 100%
need it to make the game you want to make.

Just using a variable delta_t and constraining it nicely gets you solid bang-for-buck.
*/

app_ticks: u64
frame_time: f64
last_frame_time: f64

core_app_frame :: proc "c" () {
	context = our_context

	// calculate time since last frame
	{
		current_time := seconds_since_init()
		frame_time = current_time - last_frame_time
		last_frame_time = current_time

		// clamp frame time so it doesn't go to an insane number
		MIN_FRAME_TIME :: 1.0 / 20.0
		if frame_time > MIN_FRAME_TIME {
			frame_time = MIN_FRAME_TIME
		}
	}

	// this is our delta_t for the frame
	ctx.delta_t = f32(frame_time)
	// we're just using the underlying game state for now, nothing fancy
	ctx.gs = _actual_game_state
	// also just using underlying input state, nothing fancy
	state = &_actual_input_state

	if key_pressed(.ENTER) && key_down(.LEFT_ALT) {
		sapp.toggle_fullscreen()
	}

	core_render_frame_start()
	app_frame()
	core_render_frame_end()

	reset_input_state(state)
	free_all(context.temp_allocator)

	app_ticks += 1
}

core_app_shutdown :: proc "c" () {
	context = our_context

	app_shutdown()
	sg.shutdown()
}
