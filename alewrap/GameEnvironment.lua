--[[ Copyright 2014 Google Inc.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
]]

-- This file defines the alewrap.GameEnvironment class.

-- The GameEnvironment class.
local gameEnv = torch.class('alewrap.GameEnvironment')


function gameEnv:__init(_opt,twoplayer)
    local _opt = _opt or {}
    -- defaults to emulator speed
    self.game_path      = _opt.game_path or '.'
    self.verbose        = _opt.verbose or 0
    self._actrep        = _opt.actrep or 1
    self._random_starts = _opt.random_starts or 1
    self._screen        = alewrap.GameScreen(_opt.pool_frms, _opt.gpu)

    if twoplayer then

    	self:reset2(_opt.env, _opt.env_params, _opt.gpu)

    else
    	self:reset(_opt.env, _opt.env_params, _opt.gpu)
    end	
    return self
end


function gameEnv:_updateState(frame, reward, terminal, lives)
    self._state.reward       = reward
    self._state.terminal     = terminal
    self._state.prev_lives   = self._state.lives or lives
    self._state.lives        = lives
    return self
end

function gameEnv:_updateState2(frame, rewardA,rewardB, terminal, livesA,livesB,sideBouncing,wallBouncing,points,crash,serving)
    self._state.rewardA       = rewardA
    self._state.rewardB       = rewardB
    self._state.terminal      = terminal
    self._state.prev_livesA   = self._state.livesA or livesA
    self._state.livesA        = livesA
    self._state.prev_livesB   = self._state.livesB or livesB
    self._state.livesB        = livesB
    self._state.sideBouncing  = sideBouncing
    self._state.wallBouncing  = wallBouncing
    self._state.points        = points
    self._state.crash         = crash
    self._state.serving       = serving
    return self
end

function gameEnv:getState()
    -- grab the screen again only if the state has been updated in the meantime
    self._state.observation = self._state.observation or self._screen:grab():clone()
    self._state.observation:copy(self._screen:grab())

    -- lives will not be reported externally
    return self._state.observation, self._state.reward, self._state.terminal
end
function gameEnv:getState2()

    -- grab the screen again only if the state has been updated in the meantime
    self._state.observation = self._state.observation or self._screen:grab():clone()
    self._state.observation:copy(self._screen:grab())
    -- lives will not be reported externally
    
   return self._state.observation, self._state.rewardA,self._state.rewardB, self._state.terminal,self._state.sideBouncing,self._state.wallBouncing,self._state.points,self._state.crash,self._state.serving
end


function gameEnv:reset(_env, _params, _gpu)
    local env
    local params = _params or {useRGB=true}
    -- if no game name given use previous name if available
    if self.game then
        env = self.game.name
    end
    env = _env or env or 'ms_pacman'   
    self.game       = alewrap.game(env, params, self.game_path,false)
    self._actions   = self:getActions()
    

    -- start the game
    if self.verbose > 0 then
        print('\nPlaying:', self.game.name)
    end

    self:_resetState()
    self:_updateState(self:_step(0))
    self:getState()
    return self
end
function gameEnv:reset2(_env, _params, _gpu)

    local env
    local params = _params or {useRGB=true}
    -- if no game name given use previous name if available
    if self.game then
        env = self.game.name
    end
    env = _env or env or 'ms_pacman'
    self.game       = alewrap.game(env, params, self.game_path,true)
    self._actions   = self:getActions()
    self._actionsB   = self:getActionsB()

    -- start the game
    if self.verbose > 0 then
        print('\nPlaying:', self.game.name)
    end
    self:_resetState()
    self:_updateState2(self:_step2(0,20))
    self:getState2()
    return self
end


function gameEnv:_resetState()
    self._screen:clear()
    self._state = self._state or {}
    return self
end


-- Function plays `action` in the game and return game state.
function gameEnv:_step(action)
    assert(action)
    local x = self.game:play(action)
    self._screen:paint(x.data)
    return x.data, x.reward, x.terminal, x.lives
end

function gameEnv:_step2(actionA,actionB)
    assert(actionA)
    assert(actionB)
    
    local x = self.game:play2(actionA,actionB)
    self._screen:paint(x.data)
    return x.data, x.rewardA,x.rewardB, x.terminal, x.livesA,x.livesB,x.sideBouncing,x.wallBouncing,x.points,x.crash,x.serving
end


-- Function plays one random action in the game and return game state.
function gameEnv:_randomStep()
    return self:_step(self._actions[torch.random(#self._actions)])
end
-- Function plays one random action in the game and return game state.
function gameEnv:_randomStep2()
    return self:_step2(self._actions[torch.random(#self._actions)],self._actionsB[torch.random(#self._actionsB)])
end

function gameEnv:step(action, training)
    -- accumulate rewards over actrep action repeats
    local cumulated_reward = 0
    local frame, reward, terminal, lives
    for i=1,self._actrep do
        -- Take selected action; ATARI games' actions start with action "0".
        frame, reward, terminal, lives = self:_step(action)

        -- accumulate instantaneous reward
        cumulated_reward = cumulated_reward + reward

        -- Loosing a life will trigger a terminal signal in training mode.
        -- We assume that a "life" IS an episode during training, but not during testing
        if training and lives and lives < self._state.lives then
            terminal = true
        end

        -- game over, no point to repeat current action
        if terminal then break end
    end
    self:_updateState(frame, cumulated_reward, terminal, lives)
    return self:getState()
end


function gameEnv:step2(actionA,actionB, training)
    -- accumulate rewards over actrep action repeats
    local cumulated_rewardA = 0
    local cumulated_rewardB = 0
    local frame, rewardA,rewardB, terminal, livesA,livesB,sideBouncing,wallBouncing,points,crash,serving
    for i=1,self._actrep do
        -- Take selected action; ATARI games' actions start with action "0".
        frame, rewardA,rewardB, terminal, livesA,livesB,sideBouncing,wallBouncing,points,crash,serving = self:_step2(actionA,actionB)
        cumulWallBouncing=wallBouncing or cumulWallBouncing
        -- accumulate instantaneous reward
        cumulated_rewardA = cumulated_rewardA + rewardA
        cumulated_rewardB = cumulated_rewardB + rewardB
        -- Loosing a life will trigger a terminal signal in training mode.
        -- We assume that a "life" IS an episode during training, but not during testing
        if training and livesA and livesB and (livesA < self._state.livesA or livesB <self._state.livesB) then
            terminal = true
        end

        -- game over, no point to repeat current action
        if terminal then break end
    end
    
    self:_updateState2(frame, cumulated_rewardA,cumulated_rewardB, terminal, livesA,livesB,sideBouncing,cumulWallBouncing,points,crash,serving)
    cumulWallBouncing=false
    return self:getState2()
end


--[[ Function advances the emulator state until a new game starts and returns
this state. The new game may be a different one, in the sense that playing back
the exact same sequence of actions will result in different outcomes.
]]
function gameEnv:newGame()
    local obs, reward, terminal
    terminal = self._state.terminal
    while not terminal do
        obs, reward, terminal, lives = self:_randomStep()
    end
    self._screen:clear()
    -- take one null action in the new game
    return self:_updateState(self:_step(0)):getState()
end


function gameEnv:newGame2()
    local obs, rewardA,rewardB, terminal

    terminal = self._state.terminal
    while not terminal do
        obs, rewardA,rewardB, terminal, livesA,livesB = self:_randomStep2()
    end
    self._screen:clear()
    -- take one null action in the new game
    return self:_updateState2(self:_step2(0,20)):getState2()
end

--[[ Function advances the emulator state until a new (random) game starts and
returns this state.
]]
function gameEnv:nextRandomGame(k)
    local obs, reward, terminal = self:newGame()
    k = k or torch.random(self._random_starts)
    for i=1,k-1 do
        obs, reward, terminal, lives = self:_step(0)
        if terminal then
            print(string.format('WARNING: Terminal signal received after %d 0-steps', i))
        end
    end
    return self:_updateState(self:_step(0)):getState()
end


function gameEnv:nextRandomGame2(k)
    local obs, rewardA,rewardB, terminal = self:newGame2()
    k = k or torch.random(self._random_starts)
    for i=1,k-1 do
        obs, rewardA,rewardB, terminal, livesA,livesB = self:_step2(0,20)
        if terminal then
            print(string.format('WARNING: Terminal signal received after %d 0-steps', i))
        end
    end
    return self:_updateState2(self:_step2(0,20)):getState2()
end

--[[ Function returns the number total number of pixels in one frame/observation
from the current game.
]]
function gameEnv:nObsFeature()
    return self.game:nObsFeature()
end


-- Function returns a table with valid actions in the current game.
function gameEnv:getActions()   
    return self.game:actions()
end
function gameEnv:getActionsB()
    return self.game:actionsB()
end
