// Define version of Solidity in use
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

/**
 * Giveaway contract powered by Chainlink VRF.
 * Allows creating multiple giveaways. Winners are selected uniquely,
 * i.e. a single entity cannot win a giveaway more than once.
 * 
 * For giveaways that can have the same person winning more than once,
 * a workaround is to add the same applicant again (e.g. add 'user' 5 times) 
 *
 * Flow:
 * 1. Add applicants to a giveaway ID
 * 2. Once done, roll vrf using RollVRF with that giveaway ID
 * 3. After "FulfillVRF" is emitted, use announce winners with the giveaway ID
 *
 * Once the VRF is rolled, new applicants cannot be added.
 *
 * Brought to you by PolyForge🔥⚔️
 */
contract Giveaway is Ownable, Pausable, VRFConsumerBase {
    using SafeMath for uint256;

    /**
     * Maps giveaway ID (as string) to the list of applicants.
     * Applicants should either represent addresses (as strings) or usernames.
     */
    mapping(string => string[]) public applicantPool;

    /**
     * Maps giveaway ID (as string) to the winner of the giveaway.
     */
    mapping(string => string) public winners;

    bytes32 internal _linkKeyHash;
    uint256 internal _linkFee;

    // Maps request ID to giveaway ID for drawWinner requests
    mapping(bytes32 => string) private _linkRequests;

    /** Event on drawing winner for a target giveaway */
    event DrawWinner(string indexed giveaway, bytes32 requestId);

    /** Event on announcing winner for a target giveaway */
    event AnnounceWinner(string indexed giveaway, string indexed winner);

    constructor(
        address vrfCoordinator,
        address linkToken,
        bytes32 keyHash
    )
        VRFConsumerBase(vrfCoordinator, linkToken)
    {
        _linkKeyHash = keyHash;
        _linkFee = 0.0001 * 10**18;
    }

    /**
     * Adds an applicant to the target giveaway.
     */
    function addApplicant(string memory giveawayId, string memory applicant) public onlyOwner {
        require(_compareStrings(applicant, ""), "Applicant ID cannot be empty!");
        require(_compareStrings(winners[giveawayId], ""), "Winner already determined!");

        applicantPool[giveawayId].push(applicant);
    }

    /**
     * Adds a batch of applicants to the target giveaway.
     */
    function batchAddApplicants(string memory giveawayId, string[] memory applicants) public onlyOwner {
        for (uint256 i = 0; i < applicants.length; ++i) {
            addApplicant(giveawayId, applicants[i]);
        }
    }

    /**
     * Draws winner for giveaway by requesting randomness from VRF
     */
    function drawWinner(string memory giveawayId) public onlyOwner {
        require(applicantPool[giveawayId].length > 0, "Applicants must exist in the pool!");
        require(_compareStrings(winners[giveawayId], ""), "Winner already determined!");

        bytes32 requestId = requestRandomness(_linkKeyHash, _linkFee);
        _linkRequests[requestId] = giveawayId;
        emit DrawWinner(giveawayId, requestId);
    }

    /**
     * Withdraw funds in contract
     */
    function withdraw() public onlyOwner {
        require(
            address(this).balance > 0,
            "Funds must be present in order to withdraw!"
        );
        payable(msg.sender).transfer(address(this).balance);
    }

    /**
     * Withdraws ERC-20 token funds in contract
     */
    function withdrawErc20(address tokenAddress) public onlyOwner {
        IERC20 tokenContract = IERC20(tokenAddress);
        uint256 balance = tokenContract.balanceOf(address(this));
        require(balance > 0, "Funds must be present in order to withdraw!");
        tokenContract.transfer(msg.sender, balance);
    }

    /**
     * Updates LINK fee for VRF usage
     */
    function updateLinkFee(uint256 newFee) public onlyOwner {
        _linkFee = newFee;
    }

    /**
     * Toggles pause on/off
     */
    function togglePause(bool toggle) public onlyOwner {
        if (toggle) {
            _pause();
        } else {
            _unpause();
        }
    }

    /**
     * Destroys giveaway contract
     */
    function destroy() public onlyOwner {
        selfdestruct(payable(address(this)));
    }

    /**
     * Fulfills randomness by executing a mint using the retrieved random seed.
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        string memory giveawayId = _linkRequests[requestId];
   
        if (
            !_compareStrings(giveawayId, "") &&
            _compareStrings(winners[giveawayId], "") &&
            applicantPool[giveawayId].length > 0
        ) {
            uint256 randomId = randomness % applicantPool[giveawayId].length;
            winners[giveawayId] = applicantPool[giveawayId][randomId];
            emit AnnounceWinner(giveawayId, winners[giveawayId]);
        }
    }

    /**
     * Compares 2 strings, and returns true if they are equal.
     */
    function _compareStrings(string memory str1, string memory str2)
        internal pure
        returns (bool) {
            return (keccak256(abi.encodePacked((str1))) == keccak256(abi.encodePacked((str2))));
        }
}
