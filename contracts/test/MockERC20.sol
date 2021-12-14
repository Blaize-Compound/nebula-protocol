// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract ERC20PresetMinterPauserMock is ERC20PresetMinterPauser {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 dec
    ) ERC20PresetMinterPauser(name, symbol) {
        _decimals = dec;
    }
}
