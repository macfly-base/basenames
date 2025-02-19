// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IExtendedResolver} from "ens-contracts/resolvers/profiles/IExtendedResolver.sol";
import {ERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {Ownable} from "solady/auth/Ownable.sol";

import {BASE_ETH_NAME} from "src/util/Constants.sol";
import {SignatureVerifier} from "src/lib/SignatureVerifier.sol";

/// @title L1 Resolver
/// @notice Resolver for `base.eth` on Ethereum mainnet.
///         Handles both direct resolution and offchain CCIP-Read (ERC-3668) queries.
contract L1Resolver is IExtendedResolver, ERC165, Ownable {
    
    /// @notice CCIP gateway service URL
    string public url;
    
    /// @notice Approved signers for verifying offchain responses
    mapping(address => bool) public signers;

    /// @notice Address of the root resolver for `base.eth`
    address public rootResolver;

    /// @notice Errors
    error InvalidSigner();
    error OffchainLookup(address sender, string[] urls, bytes callData, bytes4 callbackFunction, bytes extraData);

    /// @notice Events
    event AddedSigners(address[] signers);
    event UrlChanged(string newUrl);
    event RootResolverChanged(address resolver);
    event RemovedSigner(address signer);

    /// @notice Constructor
    /// @param url_ Gateway URL
    /// @param signers_ Initial approved signers
    /// @param owner_ Owner address
    /// @param rootResolver_ Address of the root resolver
    constructor(string memory url_, address[] memory signers_, address owner_, address rootResolver_) {
        url = url_;
        _initializeOwner(owner_);
        rootResolver = rootResolver_;

        for (uint256 i = 0; i < signers_.length; i++) {
            signers[signers_[i]] = true;
        }
        emit AddedSigners(signers_);
    }

    /// @notice Updates the gateway URL
    function setUrl(string calldata url_) external onlyOwner {
        url = url_;
        emit UrlChanged(url_);
    }

    /// @notice Adds new approved signers
    function addSigners(address[] calldata signers_) external onlyOwner {
        for (uint256 i; i < signers_.length; i++) {
            signers[signers_[i]] = true;
        }
        emit AddedSigners(signers_);
    }

    /// @notice Removes an approved signer
    function removeSigner(address signer) external onlyOwner {
        if (signers[signer]) {
            delete signers[signer];
            emit RemovedSigner(signer);
        }
    }

    /// @notice Sets the root resolver address
    function setRootResolver(address rootResolver_) external onlyOwner {
        rootResolver = rootResolver_;
        emit RootResolverChanged(rootResolver_);
    }

    /// @notice Computes signature hash using `SignatureVerifier`
    function makeSignatureHash(address target, uint64 expires, bytes memory request, bytes memory result)
        external
        pure
        returns (bytes32)
    {
        return SignatureVerifier.makeSignatureHash(target, expires, request, result);
    }

    /// @notice Resolves a name per ENSIP-10
    function resolve(bytes calldata name, bytes calldata data) external view override returns (bytes memory) {
        if (keccak256(BASE_ETH_NAME) == keccak256(name)) {
            return _resolve(name, data);
        }

        string[] memory urls = new string[](1);
        urls[0] = url;
        revert OffchainLookup(address(this), urls, abi.encodeWithSelector(IExtendedResolver.resolve.selector, name, data), L1Resolver.resolveWithProof.selector, abi.encode(name, data));
    }

    /// @notice Verifies and parses CCIP read responses
    function resolveWithProof(bytes calldata response, bytes calldata extraData) external view returns (bytes memory) {
        (address signer, bytes memory result) = SignatureVerifier.verify(extraData, response);
        if (!signers[signer]) revert InvalidSigner();
        return result;
    }

    /// @notice Checks supported interfaces
    function supportsInterface(bytes4 interfaceID) public view override returns (bool) {
        return interfaceID == type(IExtendedResolver).interfaceId || super.supportsInterface(interfaceID) || ERC165(rootResolver).supportsInterface(interfaceID);
    }

    /// @notice Internal method for resolving via rootResolver
    function _resolve(bytes memory, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory result) = rootResolver.staticcall(data);
        if (success) {
            return result;
        } else {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
    }

    /// @notice Forwards all calls to rootResolver (fallback function)
    fallback() external {
        address RESOLVER = rootResolver;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := call(gas(), RESOLVER, 0, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
