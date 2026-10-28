-- Colour palette
Palette = {
	navy      = {13, 59, 102},   -- Dark Blue  #0D3B66
	teal      = {0, 169, 165},   -- Teal       #00A9A5
	amber     = {255, 186, 73},  -- Amber      #FFBA49
	White     = {255, 255, 255},
	Black     = {0, 0, 0},
	Gray      = {128, 128, 128},
	Red       = {200, 40, 40},
	Green     = {40, 180, 80},
	btn_off   = {124, 124, 124},  -- #7C7C7C
	green_on  = {0, 159, 60},     -- #009F3C
	green_off = {0, 75, 22},      -- #004B16
	gray_off  = {137, 137, 137},  -- #898989
	led_off   = {16, 40, 24}
}

-- Pages shown by the plugin
PageNames = { "Control", "Setup" }

-- Layout geometry shared by both pages. Grids wrap into columns once they
-- exceed COLUMN_ROWS entries so a 32-destination router stays on screen.
Geometry = {
	COLUMN_ROWS = 16,
	rowH        = 30,
	btnW        = 30,
	btnH        = 26,
	nameW       = 132,
	srcNameW    = 150,
	fs          = 12,
	labelH      = 20
}
