-- softcut position estimator
--
-- first bar is exact position
--   from sc phase poll
-- second bar is 'dead reckoned'
--   i.e. integral of sc.rate
-- third bar is as second,
--   but also syncs to exact pos
--   when phase poll fires
--
-- E1: adjust sc.phase_quant
-- E2: adjust sc.rate
-- K2: while held, sync estimates
-- K3: reset loop counter

local sc = softcut
local rate = 0
local phase = {
  exact = {
    val = 0,
  },
  reckoned = {
    val = 0,
    jump = 0,
  },
  filtered = {
    val = 0,
    jump = 0,
  }
}
local sync = false
local loop_count = 0

function calc_jump(left, right)
  local jump = math.abs(left - right)
  if jump > size / 2 then
    jump = (size / 2) - jump
  end
  return jump
end

function phase_poll(voice, position)
  if voice == 1 then
    if position == 0 then
      loop_count = loop_count + 1
    end

    phase.exact.val = position

    if sync then
      phase.reckoned.val = phase.exact.val
      phase.reckoned.jump = 0
      phase.filtered.val = phase.exact.val
      phase.filtered.jump = 0
      return
    end

    phase.reckoned.jump = calc_jump(phase.exact.val, phase.reckoned.val)
    phase.filtered.jump = calc_jump(phase.exact.val, phase.filtered.val)

    phase.filtered.val = position
  end
end

function update_rate(x)
  sc.rate(1, x)
end

function wrap(t)
  if t > size then
    return t - size
  elseif t < 0 then
    return t + size
  else
    return t
  end
end

last_refresh = util.time()
function refresh()
  if size == 0 then
    return
  end

  local dt = 1 / 30

  local dphase = dt * params:get('rate')

  phase.reckoned.val = wrap(phase.reckoned.val + dphase)
  phase.filtered.val = wrap(phase.filtered.val + dphase)

  redraw()
end

size = 0
function load_sample(f)
  if f == '-' then
    return
  end
  print('load ' .. f)
  local chs, frames, rate = audio.file_info(f)
  size = frames / rate
  sc.loop_start(1, 0)
  sc.loop_end(1, size)
  sc.fade_time(1, 0)
  sc.buffer_read_mono(f, 0, 0, -1, 1, 1)
end

function init()
  audio.level_cut(1)
  sc.enable(1, 1)
  sc.buffer(1, 1)
  sc.level(1, 1)
  sc.loop(1, 1)
  sc.position(1, 0)
  sc.play(1, 1)
  sc.buffer_clear(1)
  sc.event_phase(phase_poll)
  sc.phase_quant(1, 0.25)
  sc.poll_start_phase()

  params:add_file('sample', 'sample')
  params:set_action('sample', function (f) load_sample(f) end)
  params:add_number('rate', 'rate', -10, 10, 1.0)
  params:set_action('rate', function(x) update_rate(x) end)
  params:bang('rate')
  params:add_number('quant', 'quant', 0.01, 2, 1.0)
  params:set_action('quant', function(x) sc.phase_quant(1, x) end)
  params:bang('quant')

  local refresh_timer = metro.init()
  refresh_timer.time = 1 / 30
  refresh_timer.event = refresh
  refresh_timer:start()
end

function enc(n, d)
  if n == 1 then
    params:delta('quant', d * 0.05)
  elseif n == 2 then
    params:delta('rate', d * 0.05)
  end
end

function key(n, d)
  if n == 2 then
    sync = d == 1
  elseif n == 3 then
    loop_count = 0
  end
end

function draw_phase(y, p)
  local x = 2
  screen.level(2)
  screen.rect(x, y, x + 120, 3)
  screen.stroke()

  local p_norm = p.val / size
  if size > 0 then
    x = 2 + util.round(p_norm * 120)
    screen.level(8)
    screen.move(x, y)
    screen.line_width(1)
    screen.line(x, y + 3)
    screen.stroke()
  end
end

function redraw()
  screen.clear()

  local x = 2
  draw_phase(2, phase.exact)
  draw_phase(8, phase.reckoned)
  draw_phase(14, phase.filtered)

  x = 0
  y = 24
  screen.level(4)
  screen.move(x, y)
  screen.text('rate: ' .. string.format('%.2f', params:get('rate')))
  x = x + 48
  screen.move(x, y)
  screen.text('exact pos: ' .. string.format('%.4f', phase.exact.val))
  x = 0
  y = 32
  screen.move(x, y)
  screen.text('qt: ' .. string.format('%.2f', params:get('quant')))
  x = x + 48
  screen.move(x, y)
  screen.text('loop #' .. loop_count)

  x = 0
  y = 48
  screen.move(x, y)
  screen.level(14)
  screen.text('current:')
  y = y + 8
  screen.move(x, y)
  screen.level(1)
  screen.text('jump:')

  x = x + 42
  y = 40
  screen.move(x, y)
  screen.level(4)
  screen.text('reckoned')
  screen.move(x, y + 8)
  screen.level(14)
  screen.text(string.format('%.4f', phase.reckoned.val))
  screen.move(x, y + 16)
  screen.level(1)
  screen.text(string.format('%.4f', phase.reckoned.jump))

  x = x + 42
  screen.move(x, y)
  screen.level(4)
  screen.text('filtered')
  screen.move(x, y + 8)
  screen.level(14)
  screen.text(string.format('%.4f', phase.filtered.val))
  screen.move(x, y + 16)
  screen.level(1)
  screen.text(string.format('%.4f', phase.filtered.jump))

  screen.update()
end
