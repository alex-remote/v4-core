// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

/// @notice 按选择器记录各函数被调用次数的 Mock 合约
/// @dev 允许代理到一个实现合约，
///  以便在需要真实逻辑或返回值时使用
contract MockContract is Proxy {
    mapping(bytes32 => uint256) public calls;
    mapping(bytes32 => mapping(bytes => uint256)) public callParams;

    /// @notice 若已设置，则在记录调用后 delegatecall 到 implementation
    address internal impl;

    function timesCalledSelector(bytes32 selector) public view returns (uint256) {
        return calls[selector];
    }

    function timesCalled(string calldata fnSig) public view returns (uint256) {
        bytes32 selector = bytes32(uint256(keccak256(bytes(fnSig))) & (type(uint256).max << 224));
        return calls[selector];
    }

    function calledWithSelector(bytes32 selector, bytes calldata params) public view returns (bool) {
        return callParams[selector][params[1:]] > 0; // 去掉 0x 字节串前缀
    }

    function calledWith(string calldata fnSig, bytes calldata params) public view returns (bool) {
        bytes32 selector = bytes32(uint256(keccak256(bytes(fnSig))) & (type(uint256).max << 224));
        return callParams[selector][params[1:]] > 0; // 去掉 0x 字节串前缀
    }

    /// @notice 暴露实现合约的地址
    function _implementation() internal view override returns (address) {
        return impl;
    }

    function setImplementation(address _impl) external {
        impl = _impl;
    }

    /// @notice 按选择器捕获调用
    function _beforeFallback() internal {
        bytes32 selector = bytes32(msg.data[:5]);
        bytes memory params = msg.data[5:];
        calls[selector]++;
        callParams[selector][params]++;
    }

    function _fallback() internal override {
        _beforeFallback();
        super._fallback();
    }

    receive() external payable {}
}
