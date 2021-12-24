// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./ControllerStorage.sol";

/**
 * @title ComptrollerCore
 * @dev Storage for the comptroller is at this address, while execution is delegated to the controllerImplementation.
 * CTokens should reference this contract as their comptroller.
 */
contract Unitroller is UnitrollerAdminStorage {
    /**
     * @notice Emitted when pendingControllerImplementation is changed
     */
    event NewPendingImplementation(address oldPendingImplementation, address newPendingImplementation);

    /**
     * @notice Emitted when pendingControllerImplementation is accepted, which means comptroller implementation is updated
     */
    event NewImplementation(address oldImplementation, address newImplementation);

    /**
     * @notice Emitted when pendingAdmin is changed
     */
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /**
     * @notice Emitted when pendingAdmin is accepted, which means admin is updated
     */
    event NewAdmin(address oldAdmin, address newAdmin);

    modifier onlyAdmin(address _caller) {
        require(_caller == admin, "Caller is not an admin");
        _;
    }

    constructor() {
        // Set admin to caller
        admin = msg.sender;
    }

    /*** Admin Functions ***/
    function setPendingImplementation(address newPendingImplementation) public onlyAdmin(msg.sender) {
        address oldPendingImplementation = pendingControllerImplementation;
        pendingControllerImplementation = newPendingImplementation;
        emit NewPendingImplementation(oldPendingImplementation, pendingControllerImplementation);
    }

    /**
     * @notice Accepts new implementation of comptroller. msg.sender must be pendingImplementation
     * @dev Admin function for new implementation to accept it's role as implementation
     */
    function acceptImplementation() public returns (bool) {
        // Check caller is pendingImplementation and pendingImplementation != address(0)
        require(
            msg.sender == pendingControllerImplementation && pendingControllerImplementation != address(0),
            "Unauthorized"
        );

        address oldImplementation = controllerImplementation;
        address oldPendingImplementation = pendingControllerImplementation;
        controllerImplementation = pendingControllerImplementation;
        pendingControllerImplementation = address(0);

        emit NewImplementation(oldImplementation, controllerImplementation);
        emit NewPendingImplementation(oldPendingImplementation, pendingControllerImplementation);

        return true;
    }

    /**
     * @notice Begins transfer of admin rights. The newPendingAdmin must call _acceptAdmin to finalize the transfer.
     * @dev Admin function to begin change of admin. The newPendingAdmin must call _acceptAdmin to finalize the transfer.
     * @param newPendingAdmin New pending admin.
     */
    function setPendingAdmin(address newPendingAdmin) public onlyAdmin(msg.sender) {
        require(newPendingAdmin != address(0), "Zero address");
        address oldPendingAdmin = pendingAdmin;
        pendingAdmin = newPendingAdmin;
        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);
    }

    /**
     * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
     * @dev Admin function for pending admin to accept role and update admin
     */
    function acceptAdmin() public {
        // Check caller is pendingAdmin and pendingAdmin != address(0)
        require(msg.sender == pendingAdmin, "Not a pending admin");
        address oldAdmin = admin;
        address oldPendingAdmin = pendingAdmin;

        // Store admin with value pendingAdmin
        admin = pendingAdmin;

        // Clear the pending value
        pendingAdmin = address(0);

        emit NewAdmin(oldAdmin, admin);
        emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);
    }

    /**
     * @dev Delegates execution to an implementation contract.
     * It returns to the external caller whatever the implementation returns
     * or forwards reverts.
     */
    fallback() external payable {
        // delegate all other functions to current implementation
        (bool success, ) = controllerImplementation.delegatecall(msg.data);

        assembly {
            let free_mem_ptr := mload(0x40)
            returndatacopy(free_mem_ptr, 0, returndatasize())

            switch success
            case 0 {
                revert(free_mem_ptr, returndatasize())
            }
            default {
                return(free_mem_ptr, returndatasize())
            }
        }
    }
}
