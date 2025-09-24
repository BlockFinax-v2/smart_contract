// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/Counters.sol";
import "../libraries/TradeStructs.sol";
import "../BaseModule.sol";

/**
 * @title ShipmentManagement
 * @dev Module for managing shipment tracking and logistics
 */
contract ShipmentManagement is BaseModule {
    using Counters for Counters.Counter;
    
    Counters.Counter private _shipmentIds;
    
    // Storage
    mapping(uint256 => TradeStructs.Shipment) public shipments;
    mapping(uint256 => uint256) public contractShipments;
    mapping(string => uint256) public trackingNumbers; // trackingNumber => shipmentId
    mapping(address => bool) public authorizedCarriers;
    mapping(address => uint256[]) public carrierShipments;
    

    
    // Events
    event ShipmentCreated(uint256 indexed shipmentId, uint256 indexed contractId, string trackingNumber);
    event ShipmentUpdated(uint256 indexed shipmentId, TradeStructs.ShipmentStatus status, string checkpoint);
    event ShipmentDelivered(uint256 indexed shipmentId, uint256 deliveryTime);
    event InsuranceClaimFiled(uint256 indexed shipmentId, uint256 claimAmount);
    event CarrierAuthorized(address indexed carrier);
    event CarrierRevoked(address indexed carrier);
    
    modifier onlyAuthorizedCarrier() {
        require(authorizedCarriers[msg.sender] || msg.sender == owner(), "Not authorized carrier");
        _;
    }
    
    /**
     * @dev Create new shipment
     */
    function createShipment(
        uint256 contractId,
        string calldata _trackingNumber,
        string calldata _carrier,
        string calldata _originAddress,
        string calldata _destinationAddress,
        uint256 _estimatedDelivery,
        uint256 _insuranceAmount
    ) external whenNotPaused returns (uint256) {
        require(contractId > 0, "Invalid contract ID");
        require(bytes(_trackingNumber).length > 0, "Tracking number required");
        require(trackingNumbers[_trackingNumber] == 0, "Tracking number already exists");
        require(_estimatedDelivery > block.timestamp, "Invalid estimated delivery time");
        require(bytes(_originAddress).length > 0, "Origin address required");
        require(bytes(_destinationAddress).length > 0, "Destination address required");
        require(contractShipments[contractId] == 0, "Shipment already exists for this contract");
        
        _shipmentIds.increment();
        uint256 shipmentId = _shipmentIds.current();
        
        shipments[shipmentId] = TradeStructs.Shipment({
            id: shipmentId,
            contractId: contractId,
            trackingNumber: _trackingNumber,
            carrier: _carrier,
            shipper: msg.sender,
            originAddress: _originAddress,
            destinationAddress: _destinationAddress,
            shipDate: block.timestamp,
            estimatedDelivery: _estimatedDelivery,
            actualDelivery: 0,
            status: TradeStructs.ShipmentStatus.Picked,
            checkpoints: new string[](0),
            insuranceClaimed: false,
            insuranceAmount: _insuranceAmount
        });
        
        contractShipments[contractId] = shipmentId;
        trackingNumbers[_trackingNumber] = shipmentId;
        carrierShipments[msg.sender].push(shipmentId);
        
        // Add initial checkpoint
        shipments[shipmentId].checkpoints.push(
            string(abi.encodePacked("Package picked up from ", _originAddress))
        );
        
        emit ShipmentCreated(shipmentId, contractId, _trackingNumber);
        
        return shipmentId;
    }
    
    /**
     * @dev Update shipment status with checkpoint
     */
    function updateShipmentStatus(
        uint256 shipmentId,
        TradeStructs.ShipmentStatus _status,
        string calldata _checkpoint
    ) public onlyAuthorizedCarrier {
        require(shipments[shipmentId].id != 0, "Shipment does not exist");
        require(bytes(_checkpoint).length > 0, "Checkpoint description required");
        
        TradeStructs.Shipment storage shipment = shipments[shipmentId];
        
        // Validate status progression
        require(_isValidStatusTransition(shipment.status, _status), "Invalid status transition");
        
        shipment.status = _status;
        shipment.checkpoints.push(_checkpoint);
        
        if (_status == TradeStructs.ShipmentStatus.Delivered) {
            shipment.actualDelivery = block.timestamp;
            emit ShipmentDelivered(shipmentId, block.timestamp);
        }
        
        emit ShipmentUpdated(shipmentId, _status, _checkpoint);
    }
    
    /**
     * @dev Batch update multiple shipments (for carriers)
     */
    function batchUpdateShipments(
        uint256[] calldata shipmentIds,
        TradeStructs.ShipmentStatus[] calldata statuses,
        string[] calldata checkpoints
    ) external onlyAuthorizedCarrier {
        require(
            shipmentIds.length == statuses.length && 
            statuses.length == checkpoints.length, 
            "Array length mismatch"
        );
        
        for (uint256 i = 0; i < shipmentIds.length; i++) {
            updateShipmentStatus(shipmentIds[i], statuses[i], checkpoints[i]);
        }
    }
    
    /**
     * @dev Report shipment as lost or damaged
     */
    function reportShipmentIssue(
        uint256 shipmentId,
        TradeStructs.ShipmentStatus _status,
        string calldata _description
    ) external onlyAuthorizedCarrier {
        require(shipments[shipmentId].id != 0, "Shipment does not exist");
        require(
            _status == TradeStructs.ShipmentStatus.Lost || 
            _status == TradeStructs.ShipmentStatus.Delayed,
            "Invalid issue status"
        );
        
        TradeStructs.Shipment storage shipment = shipments[shipmentId];
        shipment.status = _status;
        shipment.checkpoints.push(_description);
        
        emit ShipmentUpdated(shipmentId, _status, _description);
    }
    
    /**
     * @dev File insurance claim for lost/damaged shipment
     */
    function fileInsuranceClaim(uint256 shipmentId) external returns (bool) {
        require(shipments[shipmentId].id != 0, "Shipment does not exist");
        
        TradeStructs.Shipment storage shipment = shipments[shipmentId];
        require(shipment.shipper == msg.sender, "Only shipper can file claim");
        require(shipment.insuranceAmount > 0, "No insurance coverage");
        require(!shipment.insuranceClaimed, "Insurance already claimed");
        require(
            shipment.status == TradeStructs.ShipmentStatus.Lost,
            "Can only claim for lost shipments"
        );
        
        shipment.insuranceClaimed = true;
        
        emit InsuranceClaimFiled(shipmentId, shipment.insuranceAmount);
        
        return true;
    }
    
    /**
     * @dev Get shipment tracking history
     */
    function getShipmentTracking(uint256 shipmentId) external view returns (
        TradeStructs.ShipmentStatus status,
        string[] memory checkpoints,
        uint256 shipDate,
        uint256 estimatedDelivery,
        uint256 actualDelivery
    ) {
        require(shipments[shipmentId].id != 0, "Shipment does not exist");
        
        TradeStructs.Shipment memory shipment = shipments[shipmentId];
        return (
            shipment.status,
            shipment.checkpoints,
            shipment.shipDate,
            shipment.estimatedDelivery,
            shipment.actualDelivery
        );
    }
    
    /**
     * @dev Get shipment by tracking number
     */
    function getShipmentByTrackingNumber(string calldata trackingNumber) external view returns (TradeStructs.Shipment memory) {
        uint256 shipmentId = trackingNumbers[trackingNumber];
        require(shipmentId != 0, "Tracking number not found");
        return shipments[shipmentId];
    }
    
    /**
     * @dev Get shipment details
     */
    function getShipment(uint256 shipmentId) external view returns (TradeStructs.Shipment memory) {
        require(shipments[shipmentId].id != 0, "Shipment does not exist");
        return shipments[shipmentId];
    }
    
    /**
     * @dev Get contract shipment
     */
    function getContractShipment(uint256 contractId) external view returns (uint256) {
        return contractShipments[contractId];
    }
    
    /**
     * @dev Get carrier's shipments
     */
    function getCarrierShipments(address carrier) external view returns (uint256[] memory) {
        return carrierShipments[carrier];
    }
    
    /**
     * @dev Get delivery performance metrics for a carrier
     */
    function getCarrierPerformance(address carrier) external view returns (
        uint256 totalShipments,
        uint256 onTimeDeliveries,
        uint256 lateDeliveries,
        uint256 lostShipments,
        uint256 averageDeliveryTime
    ) {
        uint256[] memory shipmentIds = carrierShipments[carrier];
        totalShipments = shipmentIds.length;
        
        uint256 totalDeliveryTime = 0;
        uint256 deliveredCount = 0;
        
        for (uint256 i = 0; i < shipmentIds.length; i++) {
            TradeStructs.Shipment memory shipment = shipments[shipmentIds[i]];
            
            if (shipment.status == TradeStructs.ShipmentStatus.Delivered) {
                deliveredCount++;
                totalDeliveryTime += shipment.actualDelivery - shipment.shipDate;
                
                if (shipment.actualDelivery <= shipment.estimatedDelivery) {
                    onTimeDeliveries++;
                } else {
                    lateDeliveries++;
                }
            } else if (shipment.status == TradeStructs.ShipmentStatus.Lost) {
                lostShipments++;
            }
        }
        
        averageDeliveryTime = deliveredCount > 0 ? totalDeliveryTime / deliveredCount : 0;
    }
    
    /**
     * @dev Check if status transition is valid
     */
    function _isValidStatusTransition(
        TradeStructs.ShipmentStatus current, 
        TradeStructs.ShipmentStatus next
    ) internal pure returns (bool) {
        // Define valid state transitions
        if (current == TradeStructs.ShipmentStatus.Pending) {
            return next == TradeStructs.ShipmentStatus.Picked;
        }
        if (current == TradeStructs.ShipmentStatus.Picked) {
            return next == TradeStructs.ShipmentStatus.InTransit || 
                   next == TradeStructs.ShipmentStatus.Lost ||
                   next == TradeStructs.ShipmentStatus.Delayed;
        }
        if (current == TradeStructs.ShipmentStatus.InTransit) {
            return next == TradeStructs.ShipmentStatus.Delivered || 
                   next == TradeStructs.ShipmentStatus.Lost ||
                   next == TradeStructs.ShipmentStatus.Delayed;
        }
        if (current == TradeStructs.ShipmentStatus.Delayed) {
            return next == TradeStructs.ShipmentStatus.InTransit ||
                   next == TradeStructs.ShipmentStatus.Delivered ||
                   next == TradeStructs.ShipmentStatus.Lost;
        }
        
        // Terminal states (no transitions allowed)
        return false;
    }
    
    // Admin functions
    function authorizeCarrier(address carrier) external onlyOwner {
        authorizedCarriers[carrier] = true;
        emit CarrierAuthorized(carrier);
    }
    
    function revokeCarrier(address carrier) external onlyOwner {
        authorizedCarriers[carrier] = false;
        emit CarrierRevoked(carrier);
    }
    
    function isCarrierAuthorized(address carrier) external view returns (bool) {
        return authorizedCarriers[carrier];
    }
}