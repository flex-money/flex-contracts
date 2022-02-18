// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";

/// @title Pool
///
/// @dev A library which provides the Pool data struct and associated functions.
library Pool {
    using Pool for Pool.Data;
    using SafeMath for uint256;

    struct Data {
        uint256 rewardRate;
        uint256 rewardEndTime;
        uint256 totalDeposited;
        uint256 accumulatedRewardWeight;
        uint256 lastUpdatedTime;
    }

    /// @dev Updates the pool.
    function update(Data storage _data) internal {
        _data.accumulatedRewardWeight = _data.getUpdatedAccumulatedRewardWeight();
        _data.lastUpdatedTime = block.timestamp;
    }

    /// @dev Gets the accumulated reward weight of a pool.
    ///
    /// @return the accumulated reward weight.
    function getUpdatedAccumulatedRewardWeight(Data storage _data) internal view returns (uint256) {
        if (_data.totalDeposited == 0) {
            return _data.accumulatedRewardWeight;
        }

        if (_data.lastUpdatedTime >= _data.rewardEndTime) {
            return _data.accumulatedRewardWeight;
        }

        uint256 _now = block.timestamp;
        if (_now > _data.rewardEndTime) {
            _now = _data.rewardEndTime;
        }
        uint256 _elapsedTime = _now.sub(_data.lastUpdatedTime);
        if (_elapsedTime == 0) {
            return _data.accumulatedRewardWeight;
        }

        uint256 _distributeAmount = _data.rewardRate.mul(_elapsedTime);

        uint256 _rewardWeight = _distributeAmount.mul(1e18).div(_data.totalDeposited);
        return _data.accumulatedRewardWeight.add(_rewardWeight);
    }
}
