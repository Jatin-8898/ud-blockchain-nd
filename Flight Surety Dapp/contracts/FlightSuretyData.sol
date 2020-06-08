pragma solidity ^0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    uint public NUM_INITIAL_AIRLINES = 4;    
    uint public INSURANCE_STATUS_PAID = 1;
    uint public INSURANCE_STATUS_CLOSED = 2;
    uint public INSURANCE_STATUS_UNKNOWN = 0;
    uint public INSURANCE_STATUS_IN_PROGRESS = 1;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner; // Account used to deploy contract
    bool private operational = true; // Blocks all state changes throughout the contract if false
    mapping (address=>bool) private authorizedCallers; // Returns bool whether address is authorized or not
    struct Airline {
        bool reqApprove;
        Votes votes;
        uint256 minVotes;
        bool isFunded;
        bool isExists;
        uint256 registeredNum;
    }
    struct Votes{
        uint votersCount;
        mapping(address => bool) voters;
    }

    uint256 private airlinesCount = 0;
    mapping(address => Airline) private airlines; // Mapping to Get Airlines Struct from Address

    struct InsuranceInfo{
        address passenger;
        uint256 value;
        uint status;
    }
    mapping(bytes32 => InsuranceInfo) private insurances; // Mapping to get Insurance Info
    mapping(address => uint256) private passengerBal; // It returns Balance of Passengers
    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/

    /**
     * @dev Constructor
     *      The deploying account becomes contractOwner
     */
    constructor() public {
        contractOwner = msg.sender;
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
     * @dev Modifier that requires the "operational" boolean variable to be "true"
     *      This is used on all state changing functions to pause the contract in
     *      the event there is an issue that needs to be fixed
     */
    modifier requireIsOperational() {
        require(operational, "Contract is currently not operational");
        _; // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
     * @dev Modifier that requires the "ContractOwner" account to be the function caller
     */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    /**
     * @dev Modifier that requires the Authorized Caller contract address
     */
    modifier requireAuthorizedCaller(address contractAddress) {
         require(authorizedCallers[contractAddress] == true, "Not Authorized Caller");
        _;
    }

    /**
     * @dev Modifier that requires the Airline Exists
     */
    modifier checkAirlineExists(address airlineAddress) {
        require(airlines[airlineAddress].isExists, "Airline does't exist");
        _;
    }

    /**
     * @dev Modifier that requires that Airline is Approved
     */
    modifier checkAirlineApproved(address airlineAddress) {
        // Instaniate struct of Airline
        Airline airline = airlines[airlineAddress];
        // Check if votes >= minVotes and airline doesn't require approval
        require((airline.reqApprove == false) || (airline.votes.votersCount >= airline.minVotes), "Need approval from other Airlines");
        _;
    }

    /**
     * @dev Modifier that requires the airline has Funds
     */
    modifier checkAirlineFunds(address airlineAddress) {
        Airline memory airline = airlines[airlineAddress];
        // Check if airline is funded or not
        require(airline.isFunded != true, "Need funds");
        _;
    }
    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
     * @dev Get operating status of contract
     *
     * @return A bool that is the current operating status
     */

    function isOperational() public view returns (bool) {
        return operational;
    }

    /**
     * @dev Sets contract operations on/off
     *
     * When operational mode is disabled, all write transactions except for this one will fail
     */

    function setOperatingStatus(bool mode) external requireContractOwner {
        operational = mode;
    }
    
    /**
     * @dev Check the Airline Exists or not
     */
    function isAirline(address airlineAddress) public view requireIsOperational returns (bool) {
        return airlines[airlineAddress].isExists;
    }

    /**
     * @dev Check the Authorized Caler should be ContractOwner & should be Operational
     */
    function authorizeCaller(address contractAddress) external requireContractOwner requireIsOperational {
        authorizedCallers[contractAddress] = true;
    }
    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    /**
     * @dev Add an airline to the registration queue
     *      Can only be called from FlightSuretyApp contract
     *
     */
    function registerAirline(address airlineAddress) external requireIsOperational {
        // Create Struct of Airline
        airlines[airlineAddress] = Airline({
            reqApprove: airlinesCount >= NUM_INITIAL_AIRLINES,
            votes: Votes(0),
            minVotes: airlinesCount.add(1).div(2), // Perform count as (count+1) / 2
            isFunded: false,
            isExists: true,
            registeredNum: airlinesCount
        });
        airlinesCount = airlinesCount.add(1); // Increment the airlines count by +1
    }

    /**
     * @dev Buy insurance for a flight
     *
     */
    function buy(address passenger, bytes32 flightKey) external requireIsOperational payable {
        // Instaniate Struct of InsuranceInfo and set the variables
        insurances[flightKey] = InsuranceInfo({
            passenger: passenger,  // Address of Passenger who wants to buy
            value: msg.value,       // The Amount Passenger sent
            status: INSURANCE_STATUS_IN_PROGRESS
        });
    }

    /**
     * @dev Add vote to airline, return reqApprove Status
     *      Can only be called from FlightSuretyApp contract
     *
     */
    function voteAirline(address airlineAddress, address voterAddress) external checkAirlineExists(airlineAddress) requireIsOperational returns (bool){

        // Check if already Voted or not
        require(airlines[airlineAddress].votes.voters[voterAddress] == false, "Airline already voted by this account");

        // If not already voted, Simply Incr votersCount by 1
        airlines[airlineAddress].votes.votersCount = airlines[airlineAddress].votes.votersCount.add(1);

        // Add the voterAddress in the Votes struct
        airlines[airlineAddress].votes.voters[voterAddress] = true;

        // Set the reqApprove status 
        airlines[airlineAddress].reqApprove = airlines[airlineAddress].votes.votersCount < airlines[airlineAddress].minVotes;
        return airlines[airlineAddress].reqApprove;
    }

    /**
     *  @dev Credits payouts to insurees
     */
    function creditInsurees(bytes32 flightKey) external requireIsOperational {
        // Instaniate struct of InsuranceInfo
        InsuranceInfo insurance = insurances[flightKey];
        // If the status is in Progress (1)
        if (insurance.status == INSURANCE_STATUS_IN_PROGRESS) {
            uint256 insurancePayoutValue = getInsurancePayoutValue(flightKey);
            uint256 balance = passengerBal[insurance.passenger];
            passengerBal[insurance.passenger] = balance.add(insurancePayoutValue);
            insurance.status = INSURANCE_STATUS_PAID;
        }
    }

    /**
     *  @dev Get the Insurance Amount to Pay back to Passengers
     */
    function getInsurancePayoutValue(bytes32 flightKey) view public requireIsOperational returns(uint256){
        InsuranceInfo insurance = insurances[flightKey];
        // Calculate value by /2
        uint256 insurancePayoutValue = insurance.value.div(2);
        // Return the Payout value
        return insurancePayoutValue.add(insurance.value);
    }

    /**
     *  @dev Set the Insurance status as Closed
    */
    function closeInsurance(bytes32 flightKey) external requireIsOperational{
        InsuranceInfo insurance = insurances[flightKey];
        // if the status is not unknown then we can safely close it
        if (insurance.status != INSURANCE_STATUS_UNKNOWN) {
            insurance.status = INSURANCE_STATUS_CLOSED;
        }
    }

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
     */
    function pay(address passengerAddress) external requireIsOperational {
        // Get the Balance of Passenger
        uint256 balance = getPassengerBalance(passengerAddress);
        // Check if the balance is greater than amount to pay
        require(address(this).balance > balance, 'Not enough contact balance');
        // Set bal to 0
        passengerBal[passengerAddress] = 0;
        // Now initate the Transfer
        passengerAddress.transfer(balance);
    }

    /**
     *  @dev Get the Passenger Balance
        @return Balance as unit256
    */
    function getPassengerBalance(address passengerAddress) view public requireIsOperational returns(uint256){
        return passengerBal[passengerAddress];
    }

    /**
     * @dev Initial funding for the insurance. Unless there are too many delayed flights
     *      resulting in insurance payouts, the contract should be self-sustaining
     *
     */
    function fund(address airlineAddress) payable external requireIsOperational() checkAirlineExists(airlineAddress) checkAirlineApproved(airlineAddress){
        airlines[airlineAddress].isFunded = true;
    }

    /**
     *  @dev Get the Airlines count 
        @return Airline count as unit256
    */
    function getAirlinesCount() public view returns (uint256) {
        return airlinesCount;
    }

    function getFlightKey(
        address airline,
        string memory flight,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    /**
     * @dev Get the Airline Details from Struct
     */
    function getAirline(address airlineAddress) public view requireIsOperational 
    returns (bool isExists, 
            uint256 registeredNum, 
            bool reqApprove, 
            bool isFunded, 
            uint256 votersCount, 
            uint minVotes) 
    {
        Airline memory airline = airlines[airlineAddress];
        return (
            airline.isExists,
            airline.registeredNum,
            airline.reqApprove,
            airline.isFunded,
            airline.votes.votersCount,
            airline.minVotes
        );
    }
}