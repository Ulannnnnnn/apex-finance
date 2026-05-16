// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ApexPlatformV1} from "../../src/core/ApexPlatformV1.sol";

contract ApexPlatformV2 is ApexPlatformV1 {
    // В V2 мы добавляем новую переменную и новую функцию
    string public versionSignature;

    function setVersionSignature(string memory _sig) external onlyOwner {
        versionSignature = _sig;
    }
}
