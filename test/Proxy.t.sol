// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ApexPlatformV1} from "../src/core/ApexPlatformV1.sol";
import {ApexPlatformV2} from "./mocks/ApexPlatformV2.sol";

contract ProxyTest is Test {
    ApexPlatformV1 public proxyAsV1;
    ApexPlatformV2 public proxyAsV2;

    address public proxyAddress;
    address public owner = address(1);
    address public treasury = address(2);

    function setUp() public {
        // 1. Деплоим первую версию логики (Имплементацию)
        ApexPlatformV1 implementationV1 = new ApexPlatformV1();

        // 2. Готовим данные вызова initialize
        bytes memory initData = abi.encodeWithSelector(
            ApexPlatformV1.initialize.selector,
            30, // 0.3% комиссия
            treasury,
            owner
        );

        // 3. Деплоим сам Прокси, указывая на имплементацию и передавая данные инициализации
        vm.prank(owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementationV1), initData);
        proxyAddress = address(proxy);

        // Оборачиваем адрес прокси в интерфейс V1
        proxyAsV1 = ApexPlatformV1(proxyAddress);
    }

    function test_ProxyStorageAndInitialization() public view {
        assertEq(proxyAsV1.platformFee(), 30);
        assertEq(proxyAsV1.treasuryWallet(), treasury);
        assertEq(proxyAsV1.owner(), owner);
    }

    function test_UpgradeV1ToV2() public {
        // 1. Деплоим вторую версию логики
        ApexPlatformV2 implementationV2 = new ApexPlatformV2();

        // 2. Делаем апгрейд через прокси от имени owner
        vm.prank(owner);
        proxyAsV1.upgradeToAndCall(address(implementationV2), "");

        // 3. Теперь этот же адрес прокси можно обернуть в интерфейс V2!
        proxyAsV2 = ApexPlatformV2(proxyAddress);

        // 4. Проверяем, что старые данные в памяти СЕЙЧАС СОХРАНИЛИСЬ
        assertEq(proxyAsV2.platformFee(), 30);
        assertEq(proxyAsV2.owner(), owner);

        // 5. Проверяем, что новые функции V2 работают
        vm.prank(owner);
        proxyAsV2.setVersionSignature("Apex v2.0-L2");
        assertEq(proxyAsV2.versionSignature(), "Apex v2.0-L2");
    }
}
