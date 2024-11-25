-- Open the log file for writing
local logFile = io.open("beamng_log.csv", "w")

-- Write header row
logFile:write("Time,X,Y,Z,Speed,AccelerationX,AccelerationY,AccelerationZ,SteeringAngle,Yaw,Pitch,Roll,BrakeInput,ThrottleInput,WheelSlipFL,WheelSlipFR,WheelSlipRL,WheelSlipRR,WheelSpeedFL,WheelSpeedFR,WheelSpeedRL,WheelSpeedRR,SurfaceMaterial\n")

-- Function to log data for each simulation step
local function logData()
    local vehicle = be:getPlayerVehicle(0) -- Get the player's vehicle
    if not vehicle then return end

    -- Get positional data
    local pos = vehicle:getPosition()
    local velocity = vehicle:getVelocity()
    local acceleration = vehicle:getAcceleration()
    local orientation = vehicle:getYawPitchRoll()
    local inputs = vehicle:getInputs()

    -- Get wheel data
    local wheelData = vehicle:getWheelData() -- Returns data for all wheels
    local wheelSlip = {0, 0, 0, 0}
    local wheelSpeeds = {0, 0, 0, 0}

    for i, wheel in ipairs(wheelData) do
        wheelSlip[i] = wheel.slip or 0
        wheelSpeeds[i] = wheel.angularVelocity or 0
    end

    -- Get surface material under wheels
    local surfaceMaterial = vehicle:getSurfaceMaterial() or "Unknown"

    -- Compute speed
    local speed = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)

    -- Log all data into the CSV file
    logFile:write(string.format(
        "%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%s\n",
        os.clock(), pos.x, pos.y, pos.z, speed,
        acceleration.x, acceleration.y, acceleration.z,
        inputs.steering, orientation.yaw, orientation.pitch, orientation.roll,
        inputs.brake, inputs.throttle,
        wheelSlip[1], wheelSlip[2], wheelSlip[3], wheelSlip[4],
        wheelSpeeds[1], wheelSpeeds[2], wheelSpeeds[3], wheelSpeeds[4],
        surfaceMaterial
    ))
end

-- Attach the logData function to the simulation step callback
local function onPhysicsStep(dt)
    logData()
end

-- Register the physics step callback
be:addPhysicsStepCallback(onPhysicsStep)

-- Cleanup function to close the file when BeamNG exits
local function onExit()
    logFile:close()
end

-- Register the exit callback
be:addExitCallback(onExit)

-- Print a message to confirm the script is running
print("Data logging script loaded. Logs will be saved to beamng_log.csv")
