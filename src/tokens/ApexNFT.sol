// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ApexNFT
 * @dev VIP-пропуска в виде NFT для пользователей ApexFinance.
 * Поддерживает кастомные URI для хранения метаданных (картинок/описания).
 */
contract ApexNFT is ERC721, ERC721URIStorage, Ownable {
    uint256 private _nextTokenId;

    constructor(address initialOwner) ERC721("Apex VIP Pass", "APEX_VIP") Ownable(initialOwner) {}

    /**
     * @dev Функция безопасного минта нового NFT. Доступна только владельцу (DAO).
     * @param to Адрес получателя NFT
     * @param uri Ссылка на метаданные (IPFS хэш с картинкой и атрибутами)
     */
    function safeMint(address to, string memory uri) public onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        return tokenId;
    }

    // --- Обязательные переопределения (Overrides) для OpenZeppelin ---

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
