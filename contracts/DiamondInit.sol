// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibDiamond} from "./libraries/LibDiamond.sol";
import {LibERC20} from "./libraries/LibERC20.sol";
import {LibSwap} from "./libraries/LibSwap.sol";
import {LibTokenURI} from "./libraries/LibTokenURI.sol";
import {IDiamondCut} from "./interfaces/IDiamondCut.sol";

contract DiamondInit {
    struct InitArgs {
        string name;
        string symbol;
        uint256 initialSupply;
        uint256 tokenPriceInWei;
        string description;
        string externalUrl;
        string backgroundColor;
    }

    function init(InitArgs memory _args) external {
        LibERC20.ERC20Storage storage es = LibERC20.erc20Storage();
        es.name = _args.name;
        es.symbol = _args.symbol;
        es.decimals = 18;
        
        if (_args.initialSupply > 0) {
            address owner = LibDiamond.contractOwner();
            es.balances[owner] = _args.initialSupply;
            es.totalSupply = _args.initialSupply;
        }

        LibSwap.SwapStorage storage ss = LibSwap.swapStorage();
        ss.tokenPrice = _args.tokenPriceInWei;
        ss.swapEnabled = true;

        LibTokenURI.TokenURIStorage storage ts = LibTokenURI.tokenURIStorage();
        ts.description = _args.description;
        ts.externalUrl = _args.externalUrl;
        ts.backgroundColor = _args.backgroundColor;

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[0x01ffc9a7] = true; // ERC165
        ds.supportedInterfaces[0x48e2b093] = true; // DiamondLoupe
        ds.supportedInterfaces[0x7f5828d0] = true; // ERC173
    }
}
