// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../interfaces/IPriceOracle.sol";
import "../interfaces/IMErc20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract SimplePriceOracle is IPriceOracle {
    mapping(address => uint256) prices;
    event PricePosted(
        address asset,
        uint256 previousPriceMantissa,
        uint256 requestedPriceMantissa,
        uint256 newPriceMantissa
    );

    function _getUnderlyingAddress(IMToken mToken) private view returns (address) {
        address asset;
        asset = address(IMErc20(address(mToken)).underlying());
        return asset;
    }

    function getUnderlyingPrice(IMToken mToken) public view returns (uint256) {
        return prices[_getUnderlyingAddress(mToken)];
    }

    function setUnderlyingPrice(IMToken mToken, uint256 underlyingPriceMantissa) public {
        address asset = _getUnderlyingAddress(mToken);
        emit PricePosted(asset, prices[asset], underlyingPriceMantissa, underlyingPriceMantissa);
        prices[asset] = underlyingPriceMantissa;
    }

    function setDirectPrice(address asset, uint256 price) public {
        emit PricePosted(asset, prices[asset], price, price);
        prices[asset] = price;
    }

    // v1 price oracle interface for use as backing of proxy
    function assetPrices(address asset) external view returns (uint256) {
        return prices[asset];
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
