// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

library PuppetLib {
    bytes32 internal constant TARGET_FLAG = keccak256(bytes("PuppetLib.target"));

    function extractTargetFromCalldata() internal pure returns (address target) {
        // Look at the last 32 bytes of calldata and see if the TARGET_FLAG is there.
        uint256 length = msg.data.length;
        if (msg.data.length >= 68) {
            bytes32 flag = bytes32(msg.data[length - 32:]);

            if (flag == TARGET_FLAG) {
                // If the flag is there, extract the target from the calldata.
                target = address(bytes20(msg.data[length - 52:length - 32]));
            }
        }

        // else no target present, so target is address(0).
    }

    // function extractTargetFromCalldata() internal pure returns (address target) {
    //     // Look at the last 32 bytes of calldata and see if the TARGET_FLAG is there.
    //     bytes32 flag;
    //     assembly {
    //         flag := calldataload(sub(calldatasize(), 32))
    //     }

    //     if (flag == TARGET_FLAG) {
    //         // If the flag is there, extract the target from the calldata.
    //         assembly {
    //             target := calldataload(sub(calldatasize(), 52))
    //         }
    //     }
    //     // else no target present, so target is address(0).
    // }
}
