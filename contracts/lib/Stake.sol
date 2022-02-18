// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./Pool.sol";

/// @title Stake
///
/// @dev A library which provides the Stake data struct and associated functions.
library Stake {
    using Pool for Pool.Data;
    using Stake for Stake.Data;
    using SafeMath for uint256;

    struct Data {
        uint256 totalDeposited;
        uint256 totalUnclaimed;
        uint256 lastAccumulatedWeight;
    }

    function update(Data storage _self, Pool.Data storage _pool) internal {
        _self.totalUnclaimed = _self.getUpdatedTotalUnclaimed(_pool);
        _self.lastAccumulatedWeight = _pool.getUpdatedAccumulatedRewardWeight();
    }

    function getUpdatedTotalUnclaimed(Data storage _self, Pool.Data storage _pool) internal view returns (uint256) {
        uint256 _currentAccumulatedWeight = _pool.getUpdatedAccumulatedRewardWeight();
        uint256 _lastAccumulatedWeight = _self.lastAccumulatedWeight;

        if (_currentAccumulatedWeight == _lastAccumulatedWeight) {
            return _self.totalUnclaimed;
        }

        uint256 _distributedAmount = _currentAccumulatedWeight.sub(_lastAccumulatedWeight).mul(_self.totalDeposited).div(1e18);

        return _self.totalUnclaimed.add(_distributedAmount);
    }
}
