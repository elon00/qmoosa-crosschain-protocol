// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract MockFeeToken {
    string public name = "Fee Token";
    string public symbol = "FEET";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(balanceOf[from] >= value, "INSUFFICIENT_BALANCE");
        if (allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= value, "INSUFFICIENT_ALLOWANCE");
            allowance[from][msg.sender] -= value;
        }
        // 10% fee on transfer
        uint256 fee = (value * 10) / 100;
        uint256 net = value - fee;
        balanceOf[from] -= value;
        balanceOf[to] += net;
        balanceOf[address(0xdead)] += fee;
        return true;
    }
}
