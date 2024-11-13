// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./types/Claims.sol";
import "./types/BatchClaims.sol";
import "./types/EIP712Types.sol";

import {TheCompact} from "./TheCompact.sol";

contract HyperlaneArbiter {
    TheCompact public immutable theCompact;

    constructor(address _theCompact) {
        theCompact = TheCompact(_theCompact);
    }
}
