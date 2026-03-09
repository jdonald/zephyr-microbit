/*
 * Marble Game for BBC micro:bit V2
 *
 * A tilt-controlled marble puzzle on the 5x5 LED grid.
 * Roll the marble into the receptacle by tilting the board.
 *
 * SPDX-License-Identifier: MIT
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/display/mb_display.h>
#include <zephyr/sys/util.h>
#include <zephyr/random/random.h>

#include <math.h>
#include <string.h>

/* ---------------------------------------------------------------------------
 * Constants
 * ------------------------------------------------------------------------ */
#define GRID_SIZE        5
#define TICK_MS          30   /* game loop period */
#define ACCEL_SCALE      3.0f /* tilt-to-velocity sensitivity */
#define FRICTION         0.85f
#define MIN_DISTANCE     2    /* minimum Manhattan distance for initial placement */

/* ---------------------------------------------------------------------------
 * Types
 * ------------------------------------------------------------------------ */

/* Receptacle opening direction */
enum direction {
	DIR_UP = 0,
	DIR_DOWN,
	DIR_LEFT,
	DIR_RIGHT,
	DIR_COUNT,
};

/* ---------------------------------------------------------------------------
 * Game state
 * ------------------------------------------------------------------------ */

/* Marble position in continuous coordinates (0.0 .. 4.0) */
static float marble_x;
static float marble_y;

/* Marble velocity */
static float vel_x;
static float vel_y;

/* Receptacle grid cell */
static int recep_x;
static int recep_y;
static enum direction recep_open; /* which side is open */

/* ---------------------------------------------------------------------------
 * Random helpers
 * ------------------------------------------------------------------------ */
static int rand_range(int lo, int hi)
{
	/* Returns a value in [lo, hi] inclusive */
	uint32_t r = sys_rand32_get();
	return lo + (int)(r % (uint32_t)(hi - lo + 1));
}

/* ---------------------------------------------------------------------------
 * Level generation
 *
 * Places the receptacle centre in the inner 3×3 area (coordinates 1-3) so
 * that all three wall pixels are always on-grid and visible.  The opening
 * faces a random direction.  The marble starts at least MIN_DISTANCE
 * Manhattan-distance from the receptacle.
 * ------------------------------------------------------------------------ */
static void generate_level(void)
{
	/* Inner 3×3: guarantees every adjacent wall pixel is on-grid. */
	recep_x = rand_range(1, GRID_SIZE - 2);
	recep_y = rand_range(1, GRID_SIZE - 2);
	recep_open = (enum direction)rand_range(0, DIR_COUNT - 1);

	/* Place the marble far enough away */
	int mx, my;

	do {
		mx = rand_range(0, GRID_SIZE - 1);
		my = rand_range(0, GRID_SIZE - 1);
	} while ((abs(mx - recep_x) + abs(my - recep_y)) < MIN_DISTANCE);

	marble_x = (float)mx;
	marble_y = (float)my;
	vel_x = 0.0f;
	vel_y = 0.0f;
}

/* ---------------------------------------------------------------------------
 * Rendering helpers
 * ------------------------------------------------------------------------ */

/* Helper: light a pixel if it is within the grid */
static void set_pixel(struct mb_image *img, int x, int y)
{
	if (x >= 0 && x < GRID_SIZE && y >= 0 && y < GRID_SIZE) {
		img->row[y] |= BIT(x);
	}
}

/* Render the current game frame: marble + receptacle */
static void render_frame(struct mb_display *disp)
{
	struct mb_image frame = {};

	/* Draw the receptacle as 3 wall pixels forming an isosceles triangle.
	 * The centre cell (the "hole") is NOT drawn — the marble lights it
	 * up when it enters.  The gap in the triangle shows the open side.
	 *
	 *  Open UP:    Open DOWN:   Open LEFT:   Open RIGHT:
	 *    .            X            .X            X.
	 *   X X          X X          .X            X.
	 *    X            .           X.            .X
	 */
	if (recep_open != DIR_UP)
		set_pixel(&frame, recep_x, recep_y - 1); /* wall above */
	if (recep_open != DIR_DOWN)
		set_pixel(&frame, recep_x, recep_y + 1); /* wall below */
	if (recep_open != DIR_LEFT)
		set_pixel(&frame, recep_x - 1, recep_y); /* wall left  */
	if (recep_open != DIR_RIGHT)
		set_pixel(&frame, recep_x + 1, recep_y); /* wall right */

	/* Draw the marble (rounded to nearest pixel) */
	int mx = (int)(marble_x + 0.5f);
	int my = (int)(marble_y + 0.5f);

	mx = CLAMP(mx, 0, GRID_SIZE - 1);
	my = CLAMP(my, 0, GRID_SIZE - 1);

	set_pixel(&frame, mx, my);

	mb_display_image(disp, MB_DISPLAY_MODE_SINGLE, SYS_FOREVER_MS,
			 &frame, 1);
}

/* Star pattern for victory animation */
static const struct mb_image star = MB_IMAGE(
	{ 0, 0, 1, 0, 0 },
	{ 1, 1, 1, 1, 1 },
	{ 0, 1, 1, 1, 0 },
	{ 1, 1, 0, 1, 1 },
	{ 1, 0, 0, 0, 1 }
);

static const struct mb_image blank = MB_IMAGE(
	{ 0, 0, 0, 0, 0 },
	{ 0, 0, 0, 0, 0 },
	{ 0, 0, 0, 0, 0 },
	{ 0, 0, 0, 0, 0 },
	{ 0, 0, 0, 0, 0 }
);

/* Triple-flash the star graphic (~1 second total) */
static void victory_animation(struct mb_display *disp)
{
	for (int i = 0; i < 3; i++) {
		mb_display_image(disp, MB_DISPLAY_MODE_SINGLE, SYS_FOREVER_MS,
				 &star, 1);
		k_msleep(170);

		mb_display_image(disp, MB_DISPLAY_MODE_SINGLE, SYS_FOREVER_MS,
				 &blank, 1);
		k_msleep(170);
	}
}

/* ---------------------------------------------------------------------------
 * Collision with receptacle walls
 *
 * The receptacle occupies one grid cell and is walled on three sides.
 * When the marble is inside the receptacle cell, it can only exit through
 * the open side.
 * ------------------------------------------------------------------------ */
static bool marble_in_receptacle(void)
{
	int mx = (int)(marble_x + 0.5f);
	int my = (int)(marble_y + 0.5f);

	return (mx == recep_x && my == recep_y);
}

/* ---------------------------------------------------------------------------
 * Wall collision helpers for the receptacle
 *
 * When the marble approaches the receptacle cell from a walled side, it
 * bounces off. The open side lets the marble through.
 * ------------------------------------------------------------------------ */

/* Check if the marble is trying to enter the receptacle from a walled side
 * and, if so, prevent it. */
static void apply_receptacle_walls(float old_x, float old_y)
{
	int new_mx = (int)(marble_x + 0.5f);
	int new_my = (int)(marble_y + 0.5f);
	int old_mx = (int)(old_x + 0.5f);
	int old_my = (int)(old_y + 0.5f);

	/* Only care when marble just moved into the receptacle cell */
	if (new_mx != recep_x || new_my != recep_y) {
		return;
	}
	if (old_mx == recep_x && old_my == recep_y) {
		return; /* already inside */
	}

	/* Determine the direction of entry */
	int dx = new_mx - old_mx;
	int dy = new_my - old_my;

	bool blocked = false;

	/* Check if the entry direction is through a walled side */
	if (dx > 0 && recep_open != DIR_LEFT) {
		blocked = true; /* entering from left, but left is walled */
	} else if (dx < 0 && recep_open != DIR_RIGHT) {
		blocked = true; /* entering from right, but right is walled */
	}

	if (dy > 0 && recep_open != DIR_UP) {
		blocked = true; /* entering from top, but top is walled */
	} else if (dy < 0 && recep_open != DIR_DOWN) {
		blocked = true; /* entering from bottom, but bottom is walled */
	}

	if (blocked) {
		/* Push marble back to old position */
		marble_x = old_x;
		marble_y = old_y;
		vel_x = 0.0f;
		vel_y = 0.0f;
	}
}

/* ---------------------------------------------------------------------------
 * Physics update
 * ------------------------------------------------------------------------ */
static void update_physics(float ax, float ay)
{
	float old_x = marble_x;
	float old_y = marble_y;

	/* Accelerometer axes: tilting the board "right" gives +X accel,
	 * tilting "toward you" (down in board orientation) gives +Y.
	 * Map to LED grid: X axis = columns (left-right), Y axis = rows
	 * (top-bottom). We negate X so tilting right moves the marble
	 * rightward on the display. */
	vel_x += ax * ACCEL_SCALE * ((float)TICK_MS / 1000.0f);
	vel_y += -ay * ACCEL_SCALE * ((float)TICK_MS / 1000.0f);

	/* Friction */
	vel_x *= FRICTION;
	vel_y *= FRICTION;

	/* Update position */
	marble_x += vel_x;
	marble_y += vel_y;

	/* Clamp to grid boundaries (walled edges) */
	if (marble_x < 0.0f) {
		marble_x = 0.0f;
		vel_x = 0.0f;
	} else if (marble_x > (float)(GRID_SIZE - 1)) {
		marble_x = (float)(GRID_SIZE - 1);
		vel_x = 0.0f;
	}

	if (marble_y < 0.0f) {
		marble_y = 0.0f;
		vel_y = 0.0f;
	} else if (marble_y > (float)(GRID_SIZE - 1)) {
		marble_y = (float)(GRID_SIZE - 1);
		vel_y = 0.0f;
	}

	/* Check receptacle wall collision */
	apply_receptacle_walls(old_x, old_y);
}

/* ---------------------------------------------------------------------------
 * Main
 * ------------------------------------------------------------------------ */
int main(void)
{
	const struct device *accel = DEVICE_DT_GET_ANY(st_lsm303agr_accel);
	struct mb_display *disp = mb_display_get();

	if (accel == NULL || !device_is_ready(accel)) {
		/* Fallback: try lis2dh compatible (some DTS list it this way) */
		accel = DEVICE_DT_GET_ANY(st_lis2dh);
		if (accel == NULL || !device_is_ready(accel)) {
			mb_display_print(disp, MB_DISPLAY_MODE_DEFAULT,
					 500, "No accel!");
			return 0;
		}
	}

	/* Start the first level */
	generate_level();

	while (1) {
		struct sensor_value sv[3];
		float ax, ay;

		/* Read accelerometer */
		if (sensor_sample_fetch(accel) == 0) {
			sensor_channel_get(accel, SENSOR_CHAN_ACCEL_X, &sv[0]);
			sensor_channel_get(accel, SENSOR_CHAN_ACCEL_Y, &sv[1]);
			sensor_channel_get(accel, SENSOR_CHAN_ACCEL_Z, &sv[2]);

			ax = sensor_value_to_float(&sv[0]);
			ay = sensor_value_to_float(&sv[1]);
		} else {
			ax = 0.0f;
			ay = 0.0f;
		}

		/* Physics step */
		update_physics(ax, ay);

		/* Render */
		render_frame(disp);

		/* Check win condition */
		if (marble_in_receptacle()) {
			victory_animation(disp);
			generate_level();
		}

		k_msleep(TICK_MS);
	}

	return 0;
}
