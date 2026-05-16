// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ApexNFT} from "../src/tokens/ApexNFT.sol";

contract ApexNFTTest is Test {
    ApexNFT public nft;
    address public owner = address(1);
    address public user1 = address(2);

    function setUp() public {
        vm.prank(owner);
        nft = new ApexNFT(owner);
    }

    function test_InitialState() public view {
        assertEq(nft.name(), "Apex VIP Pass");
        assertEq(nft.symbol(), "APEX_VIP");
    }

    function test_SafeMintByOwner() public {
        string memory tokenUri = "ipfs://QmYourHashHere";

        vm.prank(owner);
        uint256 tokenId = nft.safeMint(user1, tokenUri);

        assertEq(tokenId, 0);
        assertEq(nft.ownerOf(0), user1);
        assertEq(nft.tokenURI(0), tokenUri);
    }

    function test_RevertWhen_SafeMintByNonOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));

        vm.prank(user1);
        nft.safeMint(user1, "ipfs://test");
    }
}
