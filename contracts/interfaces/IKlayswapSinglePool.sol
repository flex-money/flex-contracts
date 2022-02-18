// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IKlayswapSinglePool {
    function token() external view returns (address);

    function depositKlay() external payable;

    function depositKct(uint256 depositAmount) external;

    function withdraw(uint256 withdrawAmount) external;
}
