// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ApexToken
 * @dev Токен управления экосистемы ApexFinance с поддержкой подписей (Permit) и голосования (Votes)
 */
contract ApexToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    // Лимит максимальной эмиссии (кап) — 100 миллионов токенов
    uint256 public constant MAX_SUPPLY = 100_000_000 * 10 ** 18;

    constructor(address initialOwner)
        ERC20("Apex Finance Token", "APEX")
        ERC20Permit("Apex Finance Token")
        Ownable(initialOwner)
    {
        // Сразу минтим 10% от максимальной эмиссии на адрес создателя (например, для начальной ликвидности)
        _mint(initialOwner, 10_000_000 * 10 ** 18);
    }

    /**
     * @dev Функция создания новых токенов. Ограничена владельцем (в будущем владельцем станет DAO Timelock)
     * @param to Адрес получателя токенов
     * @param amount Количество токенов для минта
     */
    function mint(address to, uint256 amount) external onlyOwner {
        if (totalSupply() + amount > MAX_SUPPLY) {
            revert("ApexToken: Max supply exceeded");
        }
        _mint(to, amount);
    }

    // --- Обязательные переопределения (Overrides) для совместимости расширений OpenZeppelin ---

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
