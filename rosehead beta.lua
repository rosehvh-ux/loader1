local ffi = require 'ffi'
local json = require 'json'
local bit = require 'bit'
local oprint = print
local print = function(text)
    return oprint("ROSEHEAD: "..text)
end


-- UI Setup
ui.new_label("LUA", "A", "\aFF4040FF -------> Rosehead Resolver <-------")
ui.new_label("LUA", "A", "\aFF4040FF ------> Advanced Resolver <------")
local menu = {
    enabled = ui.new_checkbox("LUA", "A", "Enable Rosehead Resolver"),
    preset = ui.new_combobox("LUA", "A", "Config Preset", {"1v1", "2v2", "3v3", "Public", "DM"}),
    resolver_mode = ui.new_combobox("LUA", "A", "Resolver Mode", {"Main", "Experimental", "Experimental 2"}),
    auto_mode = ui.new_checkbox("LUA", "A", "Auto Mode"),
    backtrack_mode = ui.new_combobox("LUA", "A", "Backtrack Mode", {"Off", "Unsafe Backtrack", "Safe Backtrack"}),
    options = ui.new_multiselect("LUA", "A", "Resolver Options", {"Resolve on Miss", "Predict Movement", "Handle Defensive"}),
    aggression = ui.new_slider("LUA", "A", "Prediction Aggression", 50, 150, 90, true, "%"),
    smoothing = ui.new_slider("LUA", "A", "Prediction Smoothing", 50, 150, 100, true, "%"),
    desync_sensitivity = ui.new_slider("LUA", "A", "Desync Sensitivity", 50, 150, 90, true, "%"),
    velocity_weight = ui.new_slider("LUA", "A", "Velocity Weight", 0, 100, 40, true, "%"),
    layer_influence = ui.new_slider("LUA", "A", "Animation Layer Influence", 0, 100, 40, true, "%"),
    prediction_time_ahead = ui.new_slider("LUA", "A", "Prediction Time Ahead (ms)", 0, 200, 50, true, "ms", 0.001),
    prediction_speed_scale = ui.new_slider("LUA", "A", "Prediction Speed Scale", 0, 200, 100, true, "%", 0.01),
    prediction_process_noise = ui.new_slider("LUA", "A", "Prediction Process Noise", 0, 100, 50, true, "%", 0.01),
    prediction_measurement_noise = ui.new_slider("LUA", "A", "Prediction Measurement Noise", 0, 100, 50, true, "%", 0.01),
    prediction_defensive_damping = ui.new_slider("LUA", "A", "Defensive Damping", 0, 100, 90, true, "%", 0.01),
    prediction_defensive_jitter = ui.new_slider("LUA", "A", "Defensive Jitter", 0, 10, 2, true, "m"),
    killsay = ui.new_checkbox("LUA", "A", "Enable Killsay"),
    killsay_lang = ui.new_combobox("LUA", "A", "Killsay Language", {"English", "Russian"}),
    clear_memory = ui.new_button("LUA", "A", "Clear Memory", function()
        resolver.player_data = setmetatable({}, {__mode="v"})
        resolver.yaw_cache = {}
        resolver.layers = {}
        resolver.safepoints = {}
        resolver.stats = {hits=0, misses=0, misses_by_reason={spread=0, prediction=0, defensive=0, resolver=0}}
        for i = 0, 64 do
            resolver.yaw_cache[i] = {}
            resolver.layers[i] = {}
            resolver.safepoints[i] = {}
            for j = 0, 12 do resolver.layers[i][j] = {} end
        end
        for _, player in ipairs(entity.get_players(true)) do
            if player and entity.is_alive(player) then
                plist.set(player, "Force body yaw", false)
                plist.set(player, "Force body yaw value", 0)
            end
        end
        print("Memory cleared!")
    end),
    hit_label = ui.new_label("LUA", "A", "Hits: 0"),
    miss_label = ui.new_label("LUA", "A", "Misses: 0"),
    target_label = ui.new_label("LUA", "A", "TARGET: None")
}

-- Config Presets
local presets = {
    ["1v1"] = {
        aggression = 110,
        smoothing = 80,
        desync_sensitivity = 120,
        velocity_weight = 50,
        layer_influence = 30,
        prediction_time_ahead = 60,
        prediction_speed_scale = 110,
        prediction_process_noise = 40,
        prediction_measurement_noise = 40,
        prediction_defensive_damping = 85,
        prediction_defensive_jitter = 3,
        options = {"Resolve on Miss", "Predict Movement", "Handle Defensive"},
        backtrack_mode = "Safe Backtrack"
    },
    ["2v2"] = {
        aggression = 100,
        smoothing = 90,
        desync_sensitivity = 100,
        velocity_weight = 45,
        layer_influence = 35,
        prediction_time_ahead = 50,
        prediction_speed_scale = 100,
        prediction_process_noise = 45,
        prediction_measurement_noise = 45,
        prediction_defensive_damping = 90,
        prediction_defensive_jitter = 2,
        options = {"Resolve on Miss", "Predict Movement"},
        backtrack_mode = "Safe Backtrack"
    },
    ["3v3"] = {
        aggression = 95,
        smoothing = 95,
        desync_sensitivity = 95,
        velocity_weight = 40,
        layer_influence = 40,
        prediction_time_ahead = 45,
        prediction_speed_scale = 95,
        prediction_process_noise = 50,
        prediction_measurement_noise = 50,
        prediction_defensive_damping = 90,
        prediction_defensive_jitter = 2,
        options = {"Resolve on Miss", "Predict Movement"},
        backtrack_mode = "Safe Backtrack"
    },
    ["Public"] = {
        aggression = 90,
        smoothing = 100,
        desync_sensitivity = 90,
        velocity_weight = 35,
        layer_influence = 45,
        prediction_time_ahead = 40,
        prediction_speed_scale = 90,
        prediction_process_noise = 55,
        prediction_measurement_noise = 55,
        prediction_defensive_damping = 95,
        prediction_defensive_jitter = 1,
        options = {"Resolve on Miss"},
        backtrack_mode = "Off"
    },
    ["DM"] = {
        aggression = 120,
        smoothing = 70,
        desync_sensitivity = 130,
        velocity_weight = 60,
        layer_influence = 25,
        prediction_time_ahead = 70,
        prediction_speed_scale = 120,
        prediction_process_noise = 35,
        prediction_measurement_noise = 35,
        prediction_defensive_damping = 80,
        prediction_defensive_jitter = 4,
        options = {"Predict Movement", "Handle Defensive"},
        backtrack_mode = "Unsafe Backtrack"
    }
}

local function apply_preset(preset_name)
    local preset = presets[preset_name]
    if not preset then return end
    ui.set(menu.aggression, preset.aggression)
    ui.set(menu.smoothing, preset.smoothing)
    ui.set(menu.desync_sensitivity, preset.desync_sensitivity)
    ui.set(menu.velocity_weight, preset.velocity_weight)
    ui.set(menu.layer_influence, preset.layer_influence)
    ui.set(menu.prediction_time_ahead, preset.prediction_time_ahead)
    ui.set(menu.prediction_speed_scale, preset.prediction_speed_scale)
    ui.set(menu.prediction_process_noise, preset.prediction_process_noise)
    ui.set(menu.prediction_measurement_noise, preset.prediction_measurement_noise)
    ui.set(menu.prediction_defensive_damping, preset.prediction_defensive_damping)
    ui.set(menu.prediction_defensive_jitter, preset.prediction_defensive_jitter)
    ui.set(menu.options, preset.options)
    ui.set(menu.backtrack_mode, preset.backtrack_mode)
    print("Applied preset: " .. preset_name)
end

ui.set_callback(menu.preset, function()
    if not ui.get(menu.enabled) then return end
    apply_preset(ui.get(menu.preset))
end)

-- FFI Definitions
ffi.cdef([[
    struct c_animstate {
        char pad[3];
        char m_bForceWeaponUpdate;
        char pad1[91];
        void* m_pBaseEntity;
        void* m_pActiveWeapon;
        void* m_pLastActiveWeapon;
        float m_flLastClientSideAnimationUpdateTime;
        int m_iLastClientSideAnimationUpdateFramecount;
        float m_flAnimUpdateDelta;
        float m_flEyeYaw;
        float m_flPitch;
        float m_flGoalFeetYaw;
        float m_flCurrentFeetYaw;
        float m_flCurrentTorsoYaw;
        float m_flUnknownVelocityLean;
        float m_flLeanAmount;
        char pad2[4];
        float m_flFeetCycle;
        float m_flFeetYawRate;
        char pad3[4];
        float m_fDuckAmount;
        float m_fLandingDuckAdditiveSomething;
        char pad4[4];
        float m_vOriginX;
        float m_vOriginY;
        float m_vOriginZ;
        float m_vLastOriginX;
        float m_vLastOriginY;
        float m_vLastOriginZ;
        float m_vVelocityX;
        float m_vVelocityY;
        char pad5[4];
        float m_flUnknownFloat1;
        char pad6[8];
        float m_flUnknownFloat2;
        float m_flUnknownFloat3;
        float m_flUnknown;
        float m_flSpeed2D;
        float m_flUpVelocity;
        float m_flSpeedNormalized;
        float m_flFeetSpeedForwardsOrSideWays;
        float m_flFeetSpeedUnknownForwardOrSideways;
        float m_flTimeSinceStartedMoving;
        float m_flTimeSinceStoppedMoving;
        bool m_bOnGround;
        bool m_bInHitGroundAnimation;
        char pad7[2];
        float m_flJumpToFall;
        float m_flTimeSinceInAir;
        float m_flLastOriginZ;
        float m_flHeadHeightOrOffsetFromHittingGroundAnimation;
        float m_flStopToFullRunningFraction;
        char pad8[4];
        float m_flMagicFraction;
        char pad9[60];
        float m_flWorldForce;
        char pad10[462];
        float m_flMinYaw;
        float m_flMaxYaw;
    };
    typedef struct {
        float m_anim_time;
        float m_fade_out_time;
        int m_flags;
        int m_activity;
        int m_priority;
        int m_order;
        int m_sequence;
        float m_prev_cycle;
        float m_weight;
        float m_weight_delta_rate;
        float m_playback_rate;
        float m_cycle;
        void* m_owner;
        int m_bits;
    } C_AnimationLayer;
    typedef uintptr_t (__thiscall* GetClientEntityHandle_t)(void*, uintptr_t);
]])

-- Constants
local RESOLVER_CONST = {
    MAX_DESYNC_DELTA = 58,
    MAX_HISTORY_SIZE = 8,
    JITTER_THRESHOLD = 10,
    DEFENSIVE_YAW_CHANGE = 8,
    FAKEWALK_SPEED = 50,
    GRAVITY = -800,
    LAYER_MOVEMENT_MOVE = 6,
    POSE_PARAM_FEET_YAW = 11,
    MAX_DATA_AGE = 0.3,
    MICRO_MOVEMENT_THRESHOLD = 5
}

-- Math Utilities
local function clamp(value, min, max)
    return math.min(math.max(value, min), max)
end

local function normalize_angle(angle)
    if angle == nil then return 0 end
    while angle > 180 do angle = angle - 360 end
    while angle < -180 do angle = angle + 360 end
    return angle
end

local function angle_diff(dest, src)
    local delta = math.fmod(dest - src, 360)
    if dest > src then
        if delta >= 180 then delta = delta - 360 end
    else
        if delta <= -180 then delta = delta + 360 end
    end
    return delta
end

local function approach(target, value, speed)
    target = normalize_angle(target)
    value = normalize_angle(value)
    local delta = target - value
    if speed < 0 then speed = -speed end
    if delta < -180 then delta = delta + 360 elseif delta > 180 then delta = delta - 360 end
    if delta > speed then
        value = value + speed
    elseif delta < -speed then
        value = value - speed
    else
        value = target
    end
    return value
end

local function angle_modifier(a)
    return (360 / 65536) * bit.band(math.floor(a * (65536 / 360)), 65535)
end

-- Vector Utilities
local vec_util = {
    length2d = function(vec)
        return math.sqrt((vec.x or 0)^2 + (vec.y or 0)^2)
    end,
    get_velocity = function(player, p_data)
        if not (player and entity.is_alive(player)) then return {x=0, y=0, z=0} end
        if p_data.velocity_cache and p_data.velocity_cache_tick == globals.tickcount() then
            return p_data.velocity_cache
        end
        local vx, vy, vz = entity.get_prop(player, "m_vecVelocity")
        p_data.velocity_cache = {x=vx or 0, y=vy or 0, z=vz or 0}
        p_data.velocity_cache_tick = globals.tickcount()
        return p_data.velocity_cache
    end,
    get_origin = function(player, p_data)
        if not (player and entity.is_alive(player)) then return {x=0, y=0, z=0} end
        if p_data.origin_cache and p_data.origin_cache_tick == globals.tickcount() then
            return p_data.origin_cache
        end
        local x, y, z = entity.get_prop(player, "m_vecOrigin")
        p_data.origin_cache = {x=x or 0, y=y or 0, z=z or 0}
        p_data.origin_cache_tick = globals.tickcount()
        return p_data.origin_cache
    end
}

-- FFI Helpers
local RawIEntityList = ffi.cast("void***", client.create_interface("client.dll", "VClientEntityList003"))
local IEntityList = ffi.cast("GetClientEntityHandle_t", RawIEntityList[0][3])

local function get_address(idx)
    if not idx then return end
    local status, result = pcall(IEntityList, RawIEntityList, idx)
    if not status then
        print("Error accessing entity address for index " .. tostring(idx))
        return nil
    end
    return result
end

local function get_animstate(player)
    local ptr = get_address(player)
    if not ptr then return end
    local status, animstate = pcall(function() return ffi.cast("struct c_animstate**", ptr + 0x9960)[0] end)
    if not status or not animstate then
        print("Error accessing animstate for player " .. tostring(player))
        return nil
    end
    return animstate
end

local function get_anim_layer(player, layer)
    local ptr = get_address(player)
    if not ptr then return end
    local status, layers = pcall(function() return ffi.cast("C_AnimationLayer**", ptr + 0x2970)[0] end)
    if not status or not layers then
        print("Error accessing animation layers for player " .. tostring(player))
        return nil
    end
    return layers[layer]
end

local function get_max_desync(player)
    local animstate = get_animstate(player)
    if not animstate then return RESOLVER_CONST.MAX_DESYNC_DELTA end
    local speedfactor = clamp(animstate.m_flFeetSpeedForwardsOrSideWays or 0, 0, 1)
    local avg_speedfactor = (animstate.m_flStopToFullRunningFraction * -0.3 - 0.2) * speedfactor + 1
    local duck_amount = animstate.m_fDuckAmount or 0
    if duck_amount > 0 then
        avg_speedfactor = avg_speedfactor + ((duck_amount * speedfactor) * (0.5 - avg_speedfactor))
    end
    return clamp(avg_speedfactor * math.abs(animstate.m_flMaxYaw or RESOLVER_CONST.MAX_DESYNC_DELTA), 0.5 * RESOLVER_CONST.MAX_DESYNC_DELTA, RESOLVER_CONST.MAX_DESYNC_DELTA)
end

local function get_simulation_time(player)
    local ptr = get_address(player)
    if not ptr then return 0 end
    local sim_time = entity.get_prop(player, "m_flMPHSimulationTime") or 0
    local status, old_sim_time = pcall(function() return ffi.cast("float*", ptr + 0x26C)[0] end)
    if not status then
        print("Error accessing old simulation time for player " .. tostring(player))
        return sim_time, 0
    end
    return sim_time, old_sim_time
end

local function get_choked_packets(player)
    local current_sim_time = get_simulation_time(player)
    local sim_time_diff = toticks(entity.get_prop(player, "m_nTickBase") or 0) - (current_sim_time or 0)
    return clamp(toticks(sim_time_diff - client.latency()) or 0, 0, tonumber(cvar.sv_maxusrcmdprocessticks:get_string()) - 2)
end

-- Enhanced Kalman Filter
local function kalman_filter(state, measurement, dt, speed, prediction_settings)
    if not state or not measurement or dt <= 0 then return state end
    local process_noise = speed * prediction_settings.process_noise_factor * 0.5 + (prediction_settings.defensive_enabled and 0.08 or 0.04)
    local measurement_noise = prediction_settings.defensive_enabled and prediction_settings.measurement_noise_factor * 1.2 or prediction_settings.measurement_noise_factor
    local adaptive_factor = clamp(speed / 260, 0.5, 1.5)
    process_noise = process_noise * adaptive_factor
    measurement_noise = measurement_noise * adaptive_factor
    state.pos.x = state.pos.x + state.vel.x * dt
    state.pos.y = state.pos.y + state.vel.y * dt
    state.pos.z = state.pos.z + state.vel.z * dt
    local residual = {
        x = measurement.x - state.pos.x,
        y = measurement.y - state.pos.y,
        z = measurement.z - state.pos.z
    }
    local gain = process_noise / (process_noise + measurement_noise)
    state.pos.x = state.pos.x + gain * residual.x
    state.pos.y = state.pos.y + gain * residual.y
    state.pos.z = state.pos.z + gain * residual.z
    state.vel.x = state.vel.x + gain * residual.x / dt
    state.vel.y = state.vel.y + gain * residual.y / dt
    state.vel.z = state.vel.z + gain * residual.z / dt
    if prediction_settings.defensive_enabled then
        state.vel.x = state.vel.x * prediction_settings.defensive_damping
        state.vel.y = state.vel.y * prediction_settings.defensive_damping
        state.vel.z = state.vel.z * prediction_settings.defensive_damping
    end
    return state
end

local function predict_position(player, p_data, prediction_settings)
    if not (player and entity.is_alive(player) and p_data) then return vec_util.get_origin(player, p_data) end
    local origin = vec_util.get_origin(player, p_data)
    local velocity = vec_util.get_velocity(player, p_data)
    local speed = vec_util.length2d(velocity)
    local on_ground = bit.band(entity.get_prop(player, "m_fFlags") or 0, 1) == 1
    local state = p_data.kalman_state or {
        pos = {x=origin.x, y=origin.y, z=origin.z},
        vel = {x=velocity.x, y=velocity.y, z=velocity.z}
    }
    local tick_interval = globals.tickinterval()
    local latency = client.latency()
    local time_ahead = clamp(prediction_settings.time_ahead + latency, 0, RESOLVER_CONST.MAX_DESYNC_DELTA / 360)
    if p_data.history and #p_data.history >= 2 then
        local last_entry = p_data.history[#p_data.history]
        state = kalman_filter(state, last_entry.pos, tick_interval, speed, prediction_settings)
    end
    local pred_time = speed > 50 and time_ahead * prediction_settings.speed_scale or time_ahead
    state.pos.x = state.pos.x + state.vel.x * pred_time
    state.pos.y = state.pos.y + state.vel.y * pred_time
    state.pos.z = state.pos.z + state.vel.z * pred_time
    if not on_ground then
        local gravity_effect = 0.5 * RESOLVER_CONST.GRAVITY * pred_time * pred_time
        state.pos.z = state.pos.z + gravity_effect
        state.vel.z = state.vel.z + RESOLVER_CONST.GRAVITY * pred_time
    end
    if prediction_settings.defensive_enabled then
        state.pos.x = state.pos.x + math.random(-prediction_settings.defensive_jitter, prediction_settings.defensive_jitter)
        state.pos.y = state.pos.y + math.random(-prediction_settings.defensive_jitter, prediction_settings.defensive_jitter)
    end
    p_data.kalman_state = state
    table.insert(p_data.history, {pos={x=state.pos.x, y=state.pos.y, z=state.pos.z}, time=globals.curtime(), velocity=velocity})
    if #p_data.history > RESOLVER_CONST.MAX_HISTORY_SIZE then
        table.remove(p_data.history, 1)
    end
    return state.pos
end

-- Enhanced Yaw Prediction
local function predict_yaw(player, p_data)
    if not (player and entity.is_alive(player) and p_data) then return 0 end
    p_data.yaw_history = p_data.yaw_history or {}
    local eye_yaw = entity.get_prop(player, "m_angEyeAngles[1]") or 0
    local velocity = vec_util.get_velocity(player, p_data)
    local speed = vec_util.length2d(velocity)
    table.insert(p_data.yaw_history, {yaw=eye_yaw, tick=globals.tickcount(), speed=speed})
    if #p_data.yaw_history > RESOLVER_CONST.MAX_HISTORY_SIZE then
        table.remove(p_data.yaw_history, 1)
    end
    if #p_data.yaw_history < 3 then return eye_yaw end
    local delta1 = normalize_angle(p_data.yaw_history[#p_data.yaw_history].yaw - p_data.yaw_history[#p_data.yaw_history-1].yaw)
    local delta2 = normalize_angle(p_data.yaw_history[#p_data.yaw_history-1].yaw - p_data.yaw_history[#p_data.yaw_history-2].yaw)
    local avg_speed = (p_data.yaw_history[#p_data.yaw_history].speed + p_data.yaw_history[#p_data.yaw_history-1].speed) / 2
    local yaw_rate = (delta1 + delta2) / 2
    if avg_speed > 1.0 then
        yaw_rate = yaw_rate * (1 + avg_speed / 135)
    end
    local predicted_yaw = eye_yaw + yaw_rate
    predicted_yaw = normalize_angle(predicted_yaw)
    local cam_x, cam_y, cam_z = client.camera_position()
    local hitbox_pos = {entity.hitbox_position(player, 0)}
    local fraction, ent = client.trace_line(player, cam_x, cam_y, cam_z, hitbox_pos[1], hitbox_pos[2], hitbox_pos[3])
    local is_visible = fraction > 0.95 and ent == player
    if is_visible then
        predicted_yaw = approach(eye_yaw, predicted_yaw, 8)
    elseif avg_speed < RESOLVER_CONST.FAKEWALK_SPEED then
        predicted_yaw = approach(eye_yaw, predicted_yaw, 4)
    end
    p_data.predicted_yaw = predicted_yaw
    return predicted_yaw
end

-- Enhanced Backtrack
local tick_interval = globals.tickinterval()
local backtrack_records = {}

local function get_best_backtrack(player)
    if not backtrack_records[player] or #backtrack_records[player] == 0 then return nil end
    local current_tick = globals.tickcount()
    local max_backtrack_ticks = math.floor(0.2 / tick_interval)
    local best_record = nil
    local best_score = -1
    for i, record in ipairs(backtrack_records[player]) do
        if (current_tick - record.tick) <= max_backtrack_ticks then
            local pos = record.pos
            local fraction, ent = client.trace_line(player, client.camera_position(), pos[1], pos[2], pos[3])
            local score = fraction * (1 - (current_tick - record.tick) / max_backtrack_ticks)
            if score > best_score and fraction > 0.95 and ent == player then
                best_score = score
                best_record = record
            end
        end
    end
    if not best_record and ui.get(menu.backtrack_mode) == "Unsafe Backtrack" then
        best_record = backtrack_records[player][1]
    end
    return best_record
end

-- Resolver Data
local resolver = {
    player_data = setmetatable({}, {__mode="v"}),
    yaw_cache = {},
    layers = {},
    safepoints = {},
    stats = {hits=0, misses=0, misses_by_reason={spread=0, prediction=0, defensive=0, resolver=0}}
}
for i = 0, 64 do
    resolver.yaw_cache[i] = {}
    resolver.layers[i] = {}
    resolver.safepoints[i] = {}
    for j = 0, 12 do resolver.layers[i][j] = {} end
end

local last_angles = {}

local function get_last_angles(pl)
    return last_angles[pl] or entity.get_prop(pl, "m_angEyeAngles[1]") or 0
end

-- Resolver Logic
local function update_layers(player)
    local layers = resolver.layers[player]
    local layer_ptr = get_anim_layer(player, 6)
    if layer_ptr then
        layers[6].m_playback_rate = layer_ptr.m_playback_rate or layers[6].m_playback_rate or 0
        layers[6].m_sequence = layer_ptr.m_sequence or layers[6].m_sequence or 0
        layers[6].m_weight = layer_ptr.m_weight or layers[6].m_weight or 0
    end
end

local function update_safepoints(player, side, desync)
    local safepoints = resolver.safepoints[player]
    for i = 1, 3 do
        safepoints[i] = safepoints[i] or {}
        safepoints[i].m_playback_rate = resolver.layers[player][6].m_playback_rate or 0
        safepoints[i].m_flDesync = safepoints[i].m_flDesync or 0
    end
    if side < 0 then
        safepoints[3].m_flDesync = -desync
        safepoints[3].m_playback_rate = resolver.layers[player][6].m_playback_rate
    elseif side > 0 then
        safepoints[2].m_flDesync = desync
        safepoints[2].m_playback_rate = resolver.layers[player][6].m_playback_rate
    else
        safepoints[1].m_flDesync = side * desync
        safepoints[1].m_playback_rate = resolver.layers[player][6].m_playback_rate
    end
end

local function transition(walk_to_run, state, delta_time, velocity_len)
    local ANIM_TRANSITION_WALK_TO_RUN = false
    local ANIM_TRANSITION_RUN_TO_WALK = true
    local CSGO_ANIM_WALK_TO_RUN_TRANSITION_SPEED = 2.0
    local CS_PLAYER_SPEED_RUN = 260.0
    local CS_PLAYER_SPEED_WALK_MODIFIER = 0.52
    if walk_to_run > 0 and walk_to_run < 1 then
        if state == ANIM_TRANSITION_WALK_TO_RUN then
            walk_to_run = walk_to_run + delta_time * CSGO_ANIM_WALK_TO_RUN_TRANSITION_SPEED
        else
            walk_to_run = walk_to_run - delta_time * CSGO_ANIM_WALK_TO_RUN_TRANSITION_SPEED
        end
        walk_to_run = clamp(walk_to_run, 0, 1)
    end
    if velocity_len > (CS_PLAYER_SPEED_RUN * CS_PLAYER_SPEED_WALK_MODIFIER) and state == ANIM_TRANSITION_RUN_TO_WALK then
        state = ANIM_TRANSITION_WALK_TO_RUN
        walk_to_run = math.max(0.01, walk_to_run)
    elseif velocity_len < (CS_PLAYER_SPEED_RUN * CS_PLAYER_SPEED_WALK_MODIFIER) and state == ANIM_TRANSITION_WALK_TO_RUN then
        state = ANIM_TRANSITION_RUN_TO_WALK
        walk_to_run = math.min(0.99, walk_to_run)
    end
    return walk_to_run, state
end

local function predicted_foot_yaw(last_yaw, eye_yaw, lby_target, walk_to_run, velocity_len, min_yaw, max_yaw, aggression, smoothing, desync_sensitivity, velocity_weight, layer_influence, anim_layers)
    local foot_yaw = clamp(last_yaw, -360, 360)
    local eye_foot_delta = angle_diff(eye_yaw, foot_yaw)
    local max_desync = math.abs(max_yaw) * desync_sensitivity * 0.7
    local min_desync = math.abs(min_yaw) * desync_sensitivity * 0.7
    if eye_foot_delta > max_desync then
        foot_yaw = eye_yaw - max_desync
    elseif eye_foot_delta < min_desync then
        foot_yaw = eye_yaw + min_desync
    end
    foot_yaw = normalize_angle(foot_yaw)
    local delta_time = globals.tickinterval()
    local layer_weight = 0
    if anim_layers and anim_layers[6] and anim_layers[6].m_weight then
        layer_weight = anim_layers[6].m_weight * layer_influence
    end
    local velocity_factor = velocity_len / 260.0 * velocity_weight
    if velocity_len > 0.5 or math.abs(velocity_len) > 50 then
        foot_yaw = approach(eye_yaw, foot_yaw, delta_time * (15.0 + 10.0 * walk_to_run + layer_weight) * aggression)
    else
        foot_yaw = approach(lby_target, foot_yaw, delta_time * (60 + layer_weight) * smoothing)
    end
    return foot_yaw
end

local function antiaim_correction(player, eye_yaw)
    if not player or not eye_yaw then return 0 end
    resolver.yaw_cache[player][globals.tickcount()] = entity.get_prop(player, "m_angEyeAngles[1]") or 0
    return resolver.yaw_cache[player][globals.tickcount() - get_choked_packets(player)] or eye_yaw
end

local function resolver_instance(player, p_data, prediction_settings)
    local animstate = get_animstate(player)
    if not (entity.is_alive(player) and animstate) then return 0 end
    update_layers(player)
    p_data.cache = p_data.cache or {}
    local side = 0
    local side2 = 0
    local latest = 0
    local latest2 = 0
    local max_desync = get_max_desync(player)
    local desync = max_desync * 57.2957795131 * (prediction_settings.desync_sensitivity / 100)
    local eye_yaw = animstate.m_flEyeYaw
    local predicted_yaw = predict_yaw(player, p_data)
    local angle_diff_val = angle_diff(predicted_yaw, plist.get(player, "Force body yaw value") or 0)
    local abs_angle_diff = math.abs(angle_diff_val)
    local max_yaw_mod = max_desync * animstate.m_flMaxYaw
    local min_yaw_mod = max_desync * animstate.m_flMinYaw
    if angle_diff_val < 0 then
        side = -1
        latest = 1
    elseif angle_diff_val > 0 then
        side = 1
        latest = -1
    elseif angle_diff_val == 0 then
        side = latest
    end
    if abs_angle_diff > 0 or (p_data.cache.abs_angle_diff or 0) > 0 then
        local current_angle = math.max(abs_angle_diff, p_data.cache.abs_angle_diff or 1)
        if abs_angle_diff <= 10 and (p_data.cache.abs_angle_diff or 0) <= 10 then
            desync = current_angle
        elseif abs_angle_diff <= 35 and (p_data.cache.abs_angle_diff or 0) <= 35 then
            desync = math.max(29, current_angle)
        else
            desync = clamp(current_angle, 29, 57.2957795131 * (prediction_settings.desync_sensitivity / 100))
        end
    end
    p_data.cache.abs_angle_diff = abs_angle_diff
    desync = clamp(desync, 1, max_desync * 57.2957795131)
    update_safepoints(player, side, desync)
    if side ~= 0 and resolver.safepoints[player] then
        local server_playback = resolver.layers[player][6].m_playback_rate or 0
        local center_playback = resolver.safepoints[player][1].m_playback_rate or 0
        local left_playback = resolver.safepoints[player][2].m_playback_rate or 0
        local right_playback = resolver.safepoints[player][3].m_playback_rate or 0
        local delta1 = math.abs(server_playback - center_playback)
        local delta2 = math.abs(server_playback - left_playback)
        local delta3 = math.abs(server_playback - right_playback)
        if delta2 - delta3 > delta1 then
            side2 = 1
            latest2 = -1
        elseif delta2 - delta3 ~= delta1 then
            side2 = -1
            latest2 = 1
        else
            side2 = latest2
        end
    end
    local velocity = vec_util.get_velocity(player, p_data)
    local velocity_len = vec_util.length2d(velocity)
    p_data.cache.walk_to_run, p_data.cache.walk_to_run_state = transition(
        p_data.cache.walk_to_run or 0,
        p_data.cache.walk_to_run_state or false,
        globals.tickinterval(),
        velocity_len
    )
    p_data.desync = desync * side2
    local final_yaw = predicted_foot_yaw(
        plist.get(player, "Force body yaw value") or 0,
        predicted_yaw - p_data.desync,
        (entity.get_prop(player, "m_flLowerBodyYawTarget") or 0) - p_data.desync,
        p_data.cache.walk_to_run,
        velocity_len,
        min_yaw_mod,
        max_yaw_mod,
        prediction_settings.aggression / 100,
        prediction_settings.smoothing / 100,
        prediction_settings.desync_sensitivity / 100,
        prediction_settings.velocity_weight / 100,
        prediction_settings.layer_influence / 100,
        resolver.layers[player]
    )
    if prediction_settings.predict_movement and player == client.current_threat() then
        predict_position(player, p_data, prediction_settings)
    end
    return final_yaw
end

-- Enhanced Killsay Phrases
local killsay_phrases = {
    English = {
        "Nice try, better luck next time!",
        "You're out of your league!",
        "Rosehead owns you!",
        "Too easy, get good!",
        "Caught you slipping!",
        "Back to the spawn you go!",
        "Rosehead precision, unmatched!"
    },
    Russian = {
        "Хорошая попытка, в следующий раз повезёт!",
        "Ты не в той лиге!",
        "Rosehead тебя уделал!",
        "Слишком просто, учись играть!",
        "Попался, лошара!",
        "Возвращайся на спавн!",
        "Точность Rosehead не знает равных!"
    }
}

-- Resolver Modes
local modes = {"Main", "Experimental", "Experimental 2"}
local modes_stats = {{h=0, m=0}, {h=0, m=0}, {h=0, m=0}}
local is_auto = false
local current_mode_idx = 1
local auto_result = false
local best_mode = 1
local round_counter = 0

-- Resolver Update
local function resolver_update()
    if not ui.get(menu.enabled) then return end
    local local_player = entity.get_local_player()
    if not (local_player and entity.is_alive(local_player)) then return end
    local enemies = entity.get_players(true)
    local mode = modes[ui.get(menu.resolver_mode) + 1]
    local options = ui.get(menu.options)
    local prediction_settings = {
        aggression = ui.get(menu.aggression),
        smoothing = ui.get(menu.smoothing),
        desync_sensitivity = ui.get(menu.desync_sensitivity),
        velocity_weight = ui.get(menu.velocity_weight),
        layer_influence = ui.get(menu.layer_influence),
        time_ahead = ui.get(menu.prediction_time_ahead) / 1000,
        speed_scale = ui.get(menu.prediction_speed_scale) / 100,
        process_noise_factor = ui.get(menu.prediction_process_noise) / 100,
        measurement_noise_factor = ui.get(menu.prediction_measurement_noise) / 100,
        defensive_damping = ui.get(menu.prediction_defensive_damping) / 100,
        defensive_jitter = ui.get(menu.prediction_defensive_jitter),
        defensive_enabled = contains(options, "Handle Defensive"),
        predict_movement = contains(options, "Predict Movement")
    }
    local cur_time = globals.curtime()
    is_auto = ui.get(menu.auto_mode)

    -- Clean up stale data
    for player, data in pairs(resolver.player_data) do
        if not (player and entity.is_alive(player)) or entity.is_dormant(player) or (data.last_update or 0) + RESOLVER_CONST.MAX_DATA_AGE < cur_time then
            resolver.player_data[player] = nil
            resolver.yaw_cache[player] = {}
            resolver.layers[player] = {}
            resolver.safepoints[player] = {}
            for j = 0, 12 do resolver.layers[player][j] = {} end
        end
    end

    for _, player in ipairs(enemies) do
        if not (player and entity.is_alive(player) and not entity.is_dormant(player)) then goto continue end
        local p_data = resolver.player_data[player] or {
            desync = 0,
            history = {},
            yaw_history = {},
            last_update = cur_time,
            miss_count = 0,
            cache = {},
            defensive_triggered = false,
            velocity_cache = nil,
            velocity_cache_tick = 0,
            origin_cache = nil,
            origin_cache_tick = 0,
            kalman_state = nil,
            predicted_yaw = nil
        }
        resolver.player_data[player] = p_data

        local velocity = vec_util.get_velocity(player, p_data)
        local speed = vec_util.length2d(velocity)
        local eye_yaw = entity.get_prop(player, "m_angEyeAngles[1]") or 0
        local animstate = get_animstate(player)
        p_data.defensive_triggered = contains(options, "Handle Defensive") and (speed < RESOLVER_CONST.MICRO_MOVEMENT_THRESHOLD)

        local body_yaw = 0
        if not is_auto and mode == "Main" or (is_auto and (not auto_result and current_mode_idx == 1 or best_mode == 1)) then
            if animstate then
                local jitter_correction = antiaim_correction(player, animstate.m_flEyeYaw)
                body_yaw = normalize_angle(resolver_instance(player, p_data, prediction_settings) - jitter_correction)
                if math.abs(body_yaw) > 58 then
                    plist.set(player, "Force body yaw", false)
                else
                    plist.set(player, "Force body yaw", true)
                    plist.set(player, "Force body yaw value", clamp(body_yaw, -58, 58))
                end
            end
        elseif not is_auto and mode == "Experimental" or (is_auto and (not auto_result and current_mode_idx == 2 or best_mode == 2)) then
            if animstate then
                local goal_feet_yaw = animstate.m_flGoalFeetYaw
                local last_yaw = get_last_angles(player)
                local delta_yaw = normalize_angle(eye_yaw - goal_feet_yaw)
                local predicted_yaw = p_data.predicted_yaw or last_yaw
                if math.abs(delta_yaw) > 35 then
                    predicted_yaw = goal_feet_yaw
                end
                local normalized_speed = math.min(speed / 260, 1)
                predicted_yaw = predicted_yaw * (1 - normalized_speed * 0.5) + goal_feet_yaw * (normalized_speed * 0.5)
                local angle_delta = normalize_angle(predicted_yaw - last_yaw)
                if math.abs(angle_delta) > RESOLVER_CONST.JITTER_THRESHOLD then
                    predicted_yaw = last_yaw + angle_delta * 0.25
                else
                    predicted_yaw = last_yaw + angle_delta * 0.5
                end
                last_angles[player] = (delta_yaw / 2) + angle_delta
                body_yaw = normalize_angle(predicted_yaw)
                plist.set(player, "Force body yaw", true)
                plist.set(player, "Force body yaw value", clamp(body_yaw, -58, 58))
            end
        elseif not is_auto and mode == "Experimental 2" or (is_auto and (not auto_result and current_mode_idx == 3 or best_mode == 3)) then
            if animstate then
                local goal_feet_yaw = animstate.m_flGoalFeetYaw
                body_yaw = normalize_angle(p_data.predicted_yaw or (eye_yaw - goal_feet_yaw))
                plist.set(player, "Force body yaw", true)
                plist.set(player, "Force body yaw value", clamp(body_yaw, -58, 58))
            end
        end

        if contains(options, "Resolve on Miss") and p_data.miss_count > 0 then
            body_yaw = -body_yaw
            plist.set(player, "Force body yaw value", clamp(body_yaw, -58, 58))
        end

        p_data.last_update = cur_time
        ::continue::
    end

    ui.set(menu.hit_label, "Hits: " .. resolver.stats.hits)
    ui.set(menu.miss_label, "Misses: " .. resolver.stats.misses)
    local target = client.current_threat()
    if target and entity.is_alive(target) then
        local target_name = entity.get_player_name(target) or "ID: " .. entity.get_steam64(target)
        ui.set(menu.target_label, "TARGET: " .. target_name)
    else
        ui.set(menu.target_label, "TARGET: None")
    end
end

-- Backtrack Update
client.set_event_callback("player_update", function(e)
    local enemy_player = e.player
    if enemy_player and entity.is_enemy(enemy_player) and entity.is_alive(enemy_player) then
        local enemy_position = {entity.get_prop(enemy_player, "m_vecOrigin")}
        local current_tick = globals.tickcount()
        local simtime = entity.get_prop(enemy_player, "m_flSimulationTime")
        backtrack_records[enemy_player] = backtrack_records[enemy_player] or {}
        table.insert(backtrack_records[enemy_player], {
            pos = enemy_position,
            tick = current_tick,
            simtime = simtime
        })
        while #backtrack_records[enemy_player] > 16 do
            table.remove(backtrack_records[enemy_player], 1)
        end
    else
        backtrack_records[enemy_player] = nil
    end
end)

client.set_event_callback("setup_command", function(cmd)
    local local_player = entity.get_local_player()
    if not local_player or not entity.is_alive(local_player) then return end
    local current_threat = client.current_threat()
    if not current_threat or not entity.is_enemy(current_threat) or not entity.is_alive(current_threat) then return end
    local mode = ui.get(menu.backtrack_mode)
    if mode ~= "Off" and cmd.in_attack == 1 then
        local best_record = get_best_backtrack(current_threat)
        if best_record then
            cmd.tick_count = best_record.tick
        end
    end
end)

client.set_event_callback("shutdown", function()
    backtrack_records = {}
    for _, player in ipairs(entity.get_players(true)) do
        if player and entity.is_alive(player) then
            plist.set(player, "Force body yaw", false)
            plist.set(player, "Force body yaw value", 0)
        end
    end
end)

-- UI Visibility
local function update_ui_visibility()
    local enabled = ui.get(menu.enabled)
    ui.set_visible(menu.preset, enabled)
    ui.set_visible(menu.resolver_mode, enabled)
    ui.set_visible(menu.auto_mode, enabled)
    ui.set_visible(menu.backtrack_mode, enabled)
    ui.set_visible(menu.options, enabled)
    ui.set_visible(menu.aggression, enabled)
    ui.set_visible(menu.smoothing, enabled)
    ui.set_visible(menu.desync_sensitivity, enabled)
    ui.set_visible(menu.velocity_weight, enabled)
    ui.set_visible(menu.layer_influence, enabled)
    ui.set_visible(menu.prediction_time_ahead, enabled)
    ui.set_visible(menu.prediction_speed_scale, enabled)
    ui.set_visible(menu.prediction_process_noise, enabled)
    ui.set_visible(menu.prediction_measurement_noise, enabled)
    ui.set_visible(menu.prediction_defensive_damping, enabled)
    ui.set_visible(menu.prediction_defensive_jitter, enabled)
    ui.set_visible(menu.killsay, enabled)
    ui.set_visible(menu.killsay_lang, enabled and ui.get(menu.killsay))
    ui.set_visible(menu.clear_memory, enabled)
    ui.set_visible(menu.hit_label, enabled)
    ui.set_visible(menu.miss_label, enabled)
    ui.set_visible(menu.target_label, enabled)
    if not enabled then
        for _, player in ipairs(entity.get_players(true)) do
            if player and entity.is_alive(player) then
                plist.set(player, "Force body yaw", false)
                plist.set(player, "Force body yaw value", 0)
            end
        end
    end
end

ui.set_callback(menu.enabled, update_ui_visibility)
ui.set_callback(menu.killsay, update_ui_visibility)

ui.set_callback(menu.resolver_mode, function()
    if not ui.get(menu.enabled) then return end
    is_auto = false
    auto_result = false
    current_mode_idx = table.indexOf(modes, ui.get(menu.resolver_mode)) or 1
    print("Switched to " .. modes[current_mode_idx] .. " mode")
end)

ui.set_callback(menu.auto_mode, function()
    if not ui.get(menu.enabled) then return end
    is_auto = ui.get(menu.auto_mode)
    if is_auto then
        current_mode_idx = 1
        auto_result = false
        print("Switched to auto mode. Testing each mode every 3 rounds")
    else
        current_mode_idx = table.indexOf(modes, ui.get(menu.resolver_mode)) or 1
        print("Auto mode disabled, using " .. modes[current_mode_idx])
    end
end)

-- Event Callbacks
client.set_event_callback("net_update_start", resolver_update)

client.set_event_callback("aim_hit", function(e)
    if not ui.get(menu.enabled) then return end
    local player = e.target
    if not player then return end
    local p_data = resolver.player_data[player] or {miss_count=0}
    p_data.miss_count = math.max(0, p_data.miss_count - 1)
    resolver.player_data[player] = p_data
    resolver.stats.hits = resolver.stats.hits + 1
    if is_auto then
        modes_stats[current_mode_idx].h = modes_stats[current_mode_idx].h + 1
    end
    if ui.get(menu.killsay) and e.attacker == entity.get_local_player() and entity.get_prop(player, "m_iHealth") <= 0 then
        local lang = ui.get(menu.killsay_lang)
        local phrase = killsay_phrases[lang][math.random(#killsay_phrases[lang])]
        client.exec("say " .. phrase)
    end
end)

client.set_event_callback("aim_miss", function(e)
    if not ui.get(menu.enabled) then return end
    local player = e.target
    if not player then return end
    local p_data = resolver.player_data[player] or {miss_count=0}
    p_data.miss_count = p_data.miss_count + 1
    resolver.player_data[player] = p_data
    resolver.stats.misses = resolver.stats.misses + 1
    if is_auto then
        modes_stats[current_mode_idx].m = modes_stats[current_mode_idx].m + 1
    end
    local reason = e.reason == "spread" and "spread" or (p_data.defensive_triggered and "defensive" or "resolver")
    resolver.stats.misses_by_reason[reason] = (resolver.stats.misses_by_reason[reason] or 0) + 1
end)

client.set_event_callback("round_end", function()
    if not ui.get(menu.enabled) then return end
    round_counter = round_counter + 1
    if is_auto and round_counter >= 3 then
        if current_mode_idx == #modes then
            auto_result = true
            local best_idx = 1
            for i = 1, #modes do
                local ratio_i = modes_stats[i].m > 0 and modes_stats[i].h / modes_stats[i].m or 0
                local ratio_best = modes_stats[best_idx].m > 0 and modes_stats[best_idx].h / modes_stats[best_idx].m or 0
                if modes_stats[i].m > 0 and (ratio_i > ratio_best or modes_stats[best_idx].m == 0) then
                    best_idx = i
                end
            end
            best_mode = best_idx
            print("Selected best mode: " .. modes[best_mode])
        else
            current_mode_idx = current_mode_idx + 1
            print("Switching to " .. modes[current_mode_idx])
        end
        round_counter = 0
    end
    if not is_auto and resolver.stats.misses + 1 >= resolver.stats.hits and resolver.stats.misses + 1 > 1 then
        resolver.stats.hits = 0
        resolver.stats.misses = 0
        resolver.stats.misses_by_reason = {spread=0, prediction=0, defensive=0, resolver=0}
        print("Cleared memory due to low hitrate")
    end
    for _, player in ipairs(entity.get_players(true)) do
        if player and entity.is_alive(player) then
            plist.set(player, "Force body yaw", false)
            plist.set(player, "Force body yaw value", 0)
        end
    end
end)

client.set_event_callback("paint_ui", function()
    if not ui.get(menu.enabled) then return end
    local scr_x, scr_y = client.screen_size()
    local text_y = scr_y / 2 + 20
    if is_auto then
        if auto_result then
            renderer.text(10, text_y, 255, 255, 255, 255, nil, 999, "Selected mode: " .. modes[best_mode])
        else
            renderer.text(10, text_y, 255, 255, 255, 255, nil, 999, "Testing mode: " .. modes[current_mode_idx])
        end
    else
        renderer.text(10, text_y, 255, 255, 255, 255, nil, 999, "Mode: " .. modes[current_mode_idx])
    end
end)

-- Helper Function for Table Indexing
function table.indexOf(t, value)
    for i, v in ipairs(t) do
        if v == value then return i end
    end
    return nil
end

-- Initialization
ui.set(menu.backtrack_mode, "Off")
apply_preset("Public")
print("Rosehead Resolver loaded. Configure in LUA -> A.")