local RailroadTrain = require 'RailroadTrain'

---@class RailroadTrainFactory
---@field descriptions TrainDescription[]
local RailroadTrainFactory = class 'RailroadTrainFactory'

---@param descriptions TrainDescription[]
---@return RailroadTrainFactory
function RailroadTrainFactory.allocate(descriptions)
  return {
    descriptions = descriptions
  }
end

---@return TrainDescription
function RailroadTrainFactory:get(index)
  return RailroadTrain(table.findByProperty(self.descriptions, 'index', index) or error('No train with ID='..index))
end

---@param train RailroadTrain
function RailroadTrainFactory:release(train)
  train:dispose()
end

function RailroadTrainFactory:dispose()
  -- TODO: Dispose pools?
end

return class.emmy(RailroadTrainFactory, RailroadTrainFactory.allocate)

