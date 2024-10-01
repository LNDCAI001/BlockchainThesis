// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

// Importing Chainlink contracts for oracle integration
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

// MedicalRecords contract inherits from ChainlinkClient and ConfirmedOwner
contract MedicalRecords is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    // Struct to hold medical record data
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

    // Mapping to track patient's consent revocation
    mapping(address => mapping(address => bool)) public patientRevokedConsent;

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

    // Events to log important actions
    event RecordAdded(address indexed patient, string patientName);
    event RecordUpdated(address indexed patient, string diagnosis);
    event RecordActivated(address indexed patient);
    event RecordDeactivated(address indexed patient);
    event DoctorAuthorized(address indexed doctor);
    event DoctorDeauthorized(address indexed doctor);
    event DoctorActivationPrivilegeGranted(address indexed doctor);
    event DoctorActivationPrivilegeRevoked(address indexed doctor);
    event ConsentRevoked(address indexed patient, address indexed doctor);
    event ConsentRestored(address indexed patient, address indexed doctor);
    event RequestGAPINCheckFulfilled(bytes32 indexed requestId, bool allowed);

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

    // Constructor to set up the contract
    constructor() ConfirmedOwner(msg.sender) {
        admin = msg.sender;
        state = State.Created;
    }

    // Function to set up Chainlink oracle
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

    // Function to simulate 2FA check (for testing purposes)
    function testSetPermission(bool _allowed) public onlyAdmin {
        currentPermission = _allowed;
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
        if (patientRevokedConsent[patient][msg.sender])
            revert Unauthorized();
        records[patient].diagnosis = newDiagnosis;
        emit RecordUpdated(patient, newDiagnosis);
        currentPermission = false; // Reset permission after use
    }

    // Function to view a medical record (only callable by the patient or authorized doctors)
    function viewRecord(address patient) 
        public 
        view 
        returns (string memory patientName, uint256 dateAdded, string memory diagnosis, bool isActive) 
    {
        require(msg.sender == patient || (authorizedDoctors[msg.sender] && !patientRevokedConsent[patient][msg.sender]) || msg.sender == admin, "Unauthorized access");
        Record memory record = records[patient];
        return (record.patientName, record.dateAdded, record.diagnosis, record.isActive);
    }

    // Function for patients to revoke consent from a specific doctor
    function revokeConsent(address doctor) external {
        require(records[msg.sender].isActive, "No active record found");
        patientRevokedConsent[msg.sender][doctor] = true;
        emit ConsentRevoked(msg.sender, doctor);
    }

    // Function for patients to restore consent to a specific doctor
    function restoreConsent(address doctor) external {
        require(records[msg.sender].isActive, "No active record found");
        patientRevokedConsent[msg.sender][doctor] = false;
        emit ConsentRestored(msg.sender, doctor);
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