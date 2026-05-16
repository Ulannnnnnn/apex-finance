// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ApexNFT} from "../src/tokens/ApexNFT.sol";

contract ApexNFTTest is Test {
    ApexNFT public nft;
    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);

    function setUp() public {
        vm.prank(owner);
        nft = new ApexNFT(owner);
    }

    // --- Блок 3: Тесты NFT (6 тестов) ---

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

    function test_NftIdIncrements() public {
        vm.startPrank(owner);
        uint256 id0 = nft.safeMint(user1, "ipfs://pass1");
        uint256 id1 = nft.safeMint(user2, "ipfs://pass2");
        vm.stopPrank();

        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(nft.ownerOf(1), user2);
    }

    function test_RevertWhen_SafeMintByNonOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vm.prank(user1);
        nft.safeMint(user1, "ipfs://test");
    }

    function test_SupportsInterface() public view {
        // Проверка поддержки базовых интерфейсов ERC721 (ERC165)
        assertTrue(nft.supportsInterface(0x80ac58cd)); // ERC721 interface ID
        assertTrue(nft.supportsInterface(0x5b5e139f)); // ERC721Metadata interface ID
    }

    function test_NftTransfer() public {
        vm.prank(owner);
        nft.safeMint(user1, "ipfs://transfer-test");

        vm.prank(user1);
        nft.safeTransferFrom(user1, user2, 0);
        assertEq(nft.ownerOf(0), user2);
    }
}
