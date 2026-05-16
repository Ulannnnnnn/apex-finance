// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title ApexPlatformV1
 * @dev Главный контракт настроек платформы ApexFinance.
 * Использует UUPS паттерн прокси для обеспечения обновляемости (Mandatory ТЗ).
 */
contract ApexPlatformV1 is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // Переменные состояния платформы (Storage Layout)
    uint256 public platformFee; // Комиссия платформы (например, в базисных пунктах: 30 = 0.3%)
    address public treasuryWallet; // Кошелек для сбора комиссий
    bool public isTradingPaused; // Флаг экстренной остановки торгов

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Блокируем вызов инициализации на самом имплементационном контракте ради безопасности
        _disableInitializers();
    }

    /**
     * @dev Функция инициализации (заменяет конструктор для прокси)
     */
    function initialize(uint256 _fee, address _treasury, address _initialOwner) public initializer {
        __Ownable_init(_initialOwner);

        require(_fee <= 1000, "ApexPlatform: Fee too high"); // Максимум 10%
        platformFee = _fee;
        treasuryWallet = _treasury;
        isTradingPaused = false;
    }

    /**
     * @dev Изменение комиссии (доступно владельцу / DAO)
     */
    function setPlatformFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 1000, "ApexPlatform: Fee too high");
        platformFee = _newFee;
    }

    /**
     * @dev Управление паузой
     */
    function setPaused(bool _state) external onlyOwner {
        isTradingPaused = _state;
    }

    /**
     * @dev Обязательная функция для UUPS. Определяет, кто имеет право делать апгрейд.
     * В будущем здесь будет адрес нашего DAO Timelock.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
