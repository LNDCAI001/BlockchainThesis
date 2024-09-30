// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

// Import Chainlink contracts for oracle integration
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";



// MedicalRecords contract inherits from ChainlinkClient and ConfirmedOwner
contract MedicalRecords is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    // Structure to hold medical record data
    struct Record {
        string patientName;
        uint256 dateAdded;
        string diagnosis;
        bool isActive;
    }

    // Mapping of patient addresses to their medical records
    mapping(address => Record) public records;
    
    // Address of the contract admin (e.g., hospital administrator)
    address public admin;
    
    // Mapping to keep track of authorized doctors
    mapping(address => bool) public authorizedDoctors;

    // Mapping to track doctors with activation/deactivation privileges
    mapping(address => bool) public doctorsWithActivationPrivilege;

    // Enum to represent the state of the contract
    enum State { Created, Active, Inactive }
    State public state;

    // Chainlink specific variables
    uint256 private constant ORACLE_PAYMENT = 0.1 * 10 ** 18; // 0.1 LINK
    address private oracle;
    bytes32 private jobId;
    uint256 private fee;

    // Variable to store 2FA result
    bool private currentPermission;

    // Custom errors for better gas efficiency and clarity
    error OnlyAdmin();
    error OnlyDoctor();
    error OnlyDoctorWithActivationPrivilege();
    error InvalidState();
    error RecordNotFound();
    error Unauthorized();

    // Modifiers for access control and state management
    modifier onlyAdmin() {
        if (msg.sender != admin)
            revert OnlyAdmin();
        _;
    }

    modifier onlyDoctor() {
        if (!authorizedDoctors[msg.sender])
            revert OnlyDoctor();
        _;
    }

    modifier onlyDoctorWithActivationPrivilege() {
        if (!doctorsWithActivationPrivilege[msg.sender])
            revert OnlyDoctorWithActivationPrivilege();
        _;
    }

    modifier inState(State state_) {
        if (state != state_)
            revert InvalidState();
        _;
    }

    // New modifier for 2FA
    modifier require2FA() {
        if (!currentPermission)
            revert Unauthorized();
        _;
    }

    // Events to log important actions
    event RecordAdded(address indexed patient, string patientName);
    event RecordUpdated(address indexed patient, string diagnosis);
    event RecordActivated(address indexed patient);
    event RecordDeactivated(address indexed patient);
    event DoctorAuthorized(address indexed doctor);
    event DoctorDeauthorized(address indexed doctor);
    event DoctorActivationPrivilegeGranted(address indexed doctor);
    event DoctorActivationPrivilegeRevoked(address indexed doctor);
    event RequestGAPINCheckFulfilled(bytes32 indexed requestId, bool allowed);

    // // Constructor to set up the contract
    // constructor() ConfirmedOwner(msg.sender) {
    //     admin = msg.sender;
    //     state = State.Created;

    //     // Set the address of the LINK token for Sepolia testnet
    //     _setChainlinkToken(0x779877A7B0D9E8603169DdbD7836e478b4624789);
        
    //     // Set the oracle address (replace with actual oracle address)
    //     oracle = 0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD;
        
    //     // Set the Job ID (replace with actual Job ID)
    //     jobId = "7d80a6386ef543a3abb52817f6707e3b";
        
    //     // Set the Chainlink fee
    //     fee = 0.1 * 10 ** 18; // 0.1 LINK
    // }

    //Proper adresses 
    // oracle = 0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD
    //Job ID = c1c5e92880894eb6b27d3cae19670aa3 (for GET > bool)

    constructor() ConfirmedOwner(msg.sender) {
        admin = msg.sender;
        state = State.Created;
    }

    function setupChainlink(address _link, address _oracle, bytes32 _jobId) external onlyAdmin {
        _setChainlinkToken(_link);
        oracle = _oracle;
        jobId = _jobId;
        fee = 0.1 * 10 ** 18; // 0.1 LINK
    }

    // Function to request 2FA check
  function requestGAPINCheck(string memory _customerId, int256 _hashedpin) public {
    Chainlink.Request memory req = _buildChainlinkRequest(jobId, address(this), this.fulfillGAPINCheck.selector);
    Chainlink._add(req, "customerid", _customerId);
    Chainlink._addInt(req, "hashedpin", _hashedpin);
    Chainlink._add(req, "path", "result");
    _sendChainlinkRequestTo(oracle, req, fee);
}

    // Callback function for 2FA check
    function fulfillGAPINCheck(bytes32 _requestId, bool _allowed) public recordChainlinkFulfillment(_requestId) {
        currentPermission = _allowed;
        emit RequestGAPINCheckFulfilled(_requestId, currentPermission);
    }

    // Function to add a new medical record (only callable by authorized doctors with 2FA)
    function addRecord(address patient, string memory patientName, string memory diagnosis) 
        external 
        onlyDoctor 
        inState(State.Active)
        require2FA
    {
        records[patient] = Record(patientName, block.timestamp, diagnosis, true);
        emit RecordAdded(patient, patientName);
        currentPermission = false; // Reset permission after use
    }

    // Function to update an existing medical record (only callable by authorized doctors with 2FA)
    function updateRecord(address patient, string memory newDiagnosis) 
        external 
        onlyDoctor 
        inState(State.Active)
        require2FA
    {
        if (!records[patient].isActive)
            revert RecordNotFound();
        records[patient].diagnosis = newDiagnosis;
        emit RecordUpdated(patient, newDiagnosis);
        currentPermission = false; // Reset permission after use
    }

    // Function to activate a medical record (only callable by authorized doctors with activation privilege and 2FA)
    function activateRecord(address patient) 
        external 
        onlyDoctorWithActivationPrivilege 
        inState(State.Active)
        require2FA
    {
        if (records[patient].isActive)
            revert RecordNotFound();
        records[patient].isActive = true;
        emit RecordActivated(patient);
        currentPermission = false; // Reset permission after use
    }

    // Function to deactivate a medical record (only callable by authorized doctors with activation privilege and 2FA)
    function deactivateRecord(address patient) 
        external 
        onlyDoctorWithActivationPrivilege 
        inState(State.Active)
        require2FA
    {
        if (!records[patient].isActive)
            revert RecordNotFound();
        records[patient].isActive = false;
        emit RecordDeactivated(patient);
        currentPermission = false; // Reset permission after use
    }

    // Function to authorize a new doctor (only callable by admin)
    function authorizeDoctor(address doctor) 
        external 
        onlyAdmin 
        inState(State.Active)
    {
        authorizedDoctors[doctor] = true;
        emit DoctorAuthorized(doctor);
    }

    // Function to deauthorize a doctor (only callable by admin)
    function deauthorizeDoctor(address doctor) 
        external 
        onlyAdmin 
        inState(State.Active)
    {
        authorizedDoctors[doctor] = false;
        doctorsWithActivationPrivilege[doctor] = false;
        emit DoctorDeauthorized(doctor);
    }

    // Function to grant activation privilege to a doctor (only callable by admin)
    function grantActivationPrivilege(address doctor) 
        external 
        onlyAdmin 
        inState(State.Active)
    {
        require(authorizedDoctors[doctor], "Doctor must be authorized first");
        doctorsWithActivationPrivilege[doctor] = true;
        emit DoctorActivationPrivilegeGranted(doctor);
    }

    // Function to revoke activation privilege from a doctor (only callable by admin)
    function revokeActivationPrivilege(address doctor) 
        external 
        onlyAdmin 
        inState(State.Active)
    {
        doctorsWithActivationPrivilege[doctor] = false;
        emit DoctorActivationPrivilegeRevoked(doctor);
    }

    // Function to activate the contract (only callable by admin)
    function activateContract() external onlyAdmin inState(State.Created) {
        state = State.Active;
    }

    // Function to deactivate the contract (only callable by admin)
    function deactivateContract() external onlyAdmin inState(State.Active) {
        state = State.Inactive;
    }

    // Function to withdraw LINK tokens from the contract
    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(_chainlinkTokenAddress());
        require(link.transfer(msg.sender, link.balanceOf(address(this))), "Unable to transfer");
    }
}