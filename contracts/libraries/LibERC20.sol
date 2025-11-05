// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library LibERC20 {
    // keccak256(abi.encode(uint256(keccak256("bll.storage.erc20")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant ERC20_STORAGE_POSITION = 0x1a5c9c6c8c4d4c8e9d5f8d7b6a5e4d3c2b1a0f9e8d7c6b5a4e3d2c1b0a9e8d00;

    struct ERC20Storage {
        string name;
        string symbol;
        uint8 decimals;
        uint256 totalSupply;
        mapping(address => uint256) balances;
        mapping(address => mapping(address => uint256)) allowances;
    }

    function erc20Storage() internal pure returns (ERC20Storage storage es) {
        bytes32 position = ERC20_STORAGE_POSITION;
        assembly {
            es.slot := position
        }
    }

    function _balanceOf(address account) internal view returns (uint256) {
        return erc20Storage().balances[account];
    }

    function _totalSupply() internal view returns (uint256) {
        return erc20Storage().totalSupply;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from zero address");
        require(to != address(0), "ERC20: transfer to zero address");

        ERC20Storage storage es = erc20Storage();
        uint256 fromBalance = es.balances[from];
        require(fromBalance >= amount, "ERC20: insufficient balance");
        
        unchecked {
            es.balances[from] = fromBalance - amount;
            es.balances[to] += amount;
        }
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from zero address");
        require(spender != address(0), "ERC20: approve to zero address");

        erc20Storage().allowances[owner][spender] = amount;
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = erc20Storage().allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }
}
