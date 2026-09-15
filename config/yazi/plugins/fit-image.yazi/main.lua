local M = {}

local function canvas(area)
	local cell_w, cell_h = rt.term.cell_size()
	if not cell_w then
		return rt.preview.max_width, rt.preview.max_height
	end

	return math.min(rt.preview.max_width, math.floor(area.w * cell_w)),
		math.min(rt.preview.max_height, math.floor(area.h * cell_h))
end

function M:peek(job)
	local width, height = canvas(job.area)
	local tmp = os.tmpname()

	local output, err = Command("magick")
		:arg({
			tostring(job.file.path),
			"-auto-orient",
			"-strip",
			"-resize",
			string.format("%dx%d", width, height),
			"-quality",
			rt.preview.image_quality,
			string.format("WEBP:%s", tmp),
		})
		:stderr(Command.PIPED)
		:output()

	if not output then
		return ya.preview_widget(job, Err("Failed to start ImageMagick: %s", err))
	elseif not output.status.success then
		return ya.preview_widget(
			job,
			Err("ImageMagick exited with code %s: %s", output.status.code, output.stderr)
		)
	end

	ya.sleep(rt.preview.image_delay / 1000)
	local _, show_err = ya.image_show(Url(tmp), job.area)
	ya.preview_widget(job, show_err)
end

function M:seek() end

return M
