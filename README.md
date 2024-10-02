# MedicalRecords Smart Contract Testing Documentation

## Overview
This document provides instructions for testing the MedicalRecords smart contract. The contract manages medical records on the blockchain, with features for adding, updating, and viewing records, as well as managing doctor authorizations and patient consents.

## Environment Setup
1. Open Remix IDE: https://remix.ethereum.org/
2. Create a new file named `MedicalRecords.sol`
3. Copy and paste the provided smart contract code into this file

## Contract Versions
We have two versions of the contract:
1. Simplified Testing Version: For quick tests in Remix VM
2. Full Version with Chainlink: For comprehensive testing, including 2FA simulation

## Compilation
1. In Remix, go to the "Solidity Compiler" tab
2. Select compiler version 0.8.4 or higher
3. Click "Compile MedicalRecords.sol"

## Deployment and Testing

### A. Simplified Testing Version (Remix VM)

1. Deploy the Contract:
   - Go to the "Deploy & Run Transactions" tab
   - Select "Remix VM (London)" from the Environment dropdown
   - Click "Deploy"

2. Activate the Contract:
   - Call `activateContract()`

3. Authorize a Doctor:
   - Call `authorizeDoctor(address)` with a test address

4. Simulate 2FA:
   - Call `testSetPermission(true)` to simulate a successful 2FA check

5. Add a Medical Record:
   - Call `addRecord(address patient, string patientName, string diagnosis)`

6. View the Record:
   - Call `viewRecord(address patient)` with the patient's address

7. Update the Record:
   - First, call `testSetPermission(true)` again
   - Then call `updateRecord(address patient, string newDiagnosis)`

8. Test Patient Consent:
   - Use a different account to call `revokeConsent(address doctor)`
   - Try updating the record again - it should fail
   - Call `restoreConsent(address doctor)` to restore access

### B. Full Version with Chainlink (Sepolia Testnet)

Prerequisites:
- MetaMask installed with Sepolia testnet configured
- Sepolia ETH in your account (from a faucet)
- Sepolia LINK tokens (from a Chainlink faucet)

1. Deploy the Contract:
   - In Remix, select "Injected Provider - MetaMask" from the Environment dropdown
   - Ensure MetaMask is connected to Sepolia testnet
   - Click "Deploy" and confirm the transaction in MetaMask

2. Setup Chainlink:
   - Call `setupChainlink` with these parameters:
     - _link: 0x779877A7B0D9E8603169DdbD7836e478b4624789 (Sepolia LINK token address)
     - _oracle: 0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD (Chainlink oracle address)
     - _jobId: 0x6331633565393238383038393465623662323764336361653139363730616133 
       (bytes32 representation of "c1c5e92880894eb6b27d3cae19670aa3")

3. Activate the Contract:
   - Call `activateContract()`

4. Authorize a Doctor:
   - Call `authorizeDoctor(address)` with a test address

5. Request 2FA Check:
   - Call `requestGAPINCheck(string customerId, int256 hashedpin)`
   - Note: In a real environment, this would trigger an oracle response
   - For testing, manually call `fulfillGAPINCheck(bytes32 _requestId, bool _allowed)`
     with `_allowed` set to true

6. Add a Medical Record:
   - Immediately after the 2FA check, call `addRecord(address patient, string patientName, string diagnosis)`

7. View the Record:
   - Call `viewRecord(address patient)` with the patient's address

8. Update the Record:
   - Repeat steps 5-6 for 2FA
   - Call `updateRecord(address patient, string newDiagnosis)`

9. Test Patient Consent:
   - Use a different account to call `revokeConsent(address doctor)`
   - Try updating the record again - it should fail
   - Call `restoreConsent(address doctor)` to restore access

## Key Functions for Testing

- `activateContract()`: Activates the contract (admin only)
- `authorizeDoctor(address)`: Authorizes a doctor (admin only)
- `addRecord(address, string, string)`: Adds a new medical record (authorized doctors only, requires 2FA)
- `updateRecord(address, string)`: Updates an existing record (authorized doctors only, requires 2FA)
- `viewRecord(address)`: Views a patient's record (patient, authorized doctors, or admin)
- `revokeConsent(address)`: Revokes a doctor's access to patient's record (patient only)
- `restoreConsent(address)`: Restores a doctor's access (patient only)

## Notes for Supervisor

1. The simplified version allows for quick testing of core functionalities without the need for external services or testnet ETH.

2. The full version with Chainlink demonstrates how the contract would work in a more realistic setting, including external 2FA checks.

3. In both versions, ensure to test all access controls:
   - Only admin can authorize doctors
   - Only authorized doctors can add/update records
   - Patients can view their own records and manage doctor access
   - Unauthorized attempts should fail

4. The Chainlink integration in the full version simulates a real-world 2FA process. In a production environment, this would connect to an actual external 2FA service.

5. Gas costs and transaction times will be higher in the full version on Sepolia testnet compared to the Remix VM environment.

6. Always use test data, never real patient information, during these tests.

7. For a production deployment, additional security audits and optimizations would be necessary.

By following these steps, you can thoroughly test the functionality and security features of the MedicalRecords smart contract in both a simplified local environment and a more realistic testnet setting.
