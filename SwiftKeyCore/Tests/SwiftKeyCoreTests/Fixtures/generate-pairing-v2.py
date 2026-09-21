#!/usr/bin/env python3
"""Independent v2 vectors: Python struct/hashlib + cryptography ECDSA, no Swift encoder.
Run from any directory; writes pairing-v2-vectors.json next to this file.
"""
import base64, hashlib, json, struct
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

# Field ordering transcribed from protocol rev 0.2, independently of Swift models.
C = [('authorityID','b'),('origin','s'),('audience','s')]
S = {
'OwnerDescriptor': ('owner-descriptor-v2',[('deviceID','s'),('rootKind','s'),('rootKeyEpoch','u'),('rootPublicKey','b'),('attestationReceiptHash','b'),('role','s')]),
'PreEnrollmentChallenge': ('preaccount-enrollment-v2',C+[('challengeID','s'),('requestID','s'),('deviceID','s'),('rootKind','s'),('trustPolicyID','s'),('nonce','b'),('issuedAt','u'),('expiresAt','u')]),
'AttestationEvidence': ('attestation-evidence-v2',[('rootKind','s'),('certificates','[b]')]),
'DeviceTrustReceipt': ('device-trust-receipt-v2',C+[('deviceID','s'),('rootKind','s'),('rootKeyEpoch','u'),('rootPublicKey','b'),('originalChallengeHash','b'),('evidenceHash','b'),('trustPolicyID','s'),('verifiedAt','u'),('leaseExpiresAt','u')]),
'AccountRoster': ('account-roster-v2',C+[('accountID','s'),('accountLabel','s'),('ownershipPolicyID','s'),('membershipRevision','u'),('owners','[OwnerDescriptor]'),('issuedAt','u'),('expiresAt','u')]),
'ExistingAccountContext': ('existing-account-context-v2',[('accountID','s'),('accountLabel','s'),('ownershipPolicyID','s'),('membershipRevision','u'),('existingOwners','[OwnerDescriptor]'),('lostOwner','?OwnerDescriptor')]),
'PairingContext': ('pairing-context-v2',[('purpose','s'),('existingAccount','?ExistingAccountContext')]),
'CreatePairingIntent': ('create-pairing-v2',C+[('requestID','s'),('initiator','OwnerDescriptor'),('context','PairingContext')]),
'PairingInspection': ('pairing-inspection-v2',C+[('pairingID','s'),('revision','u'),('initiator','OwnerDescriptor'),('context','PairingContext'),('issuedAt','u'),('expiresAt','u')]),
'JoinPairingIntent': ('join-pairing-v2',C+[('pairingID','s'),('expectedRevision','u'),('inspectionHash','b'),('initiatorHash','b'),('candidate','OwnerDescriptor')]),
'PairTranscript': ('pair-transcript-v2',C+[('pairingID','s'),('revision','u'),('context','PairingContext'),('owners','[OwnerDescriptor]'),('nonce','b'),('issuedAt','u'),('expiresAt','u')]),
'ProposeAccountIntent': ('propose-account-v2',C+[('pairingID','s'),('expectedRevision','u'),('pairReceiptHash','b'),('label','s'),('ownershipPolicyID','s')]),
'ReplaceGenesisIntent': ('replace-genesis-v2',C+[('pairingID','s'),('expectedRevision','u'),('oldProposalHash','b'),('newLabel','s'),('newOwnershipPolicyID','s')]),
'RenewLeaseIntent': ('renew-identity-lease-v2',C+[('deviceID','s'),('rootKeyEpoch','u'),('existingTrustReceiptHash','b')]),
'AccountGenesis': ('account-genesis-v2',C+[('proposalID','s'),('pairingID','s'),('pairTranscriptHash','b'),('accountID','s'),('label','s'),('owners','[OwnerDescriptor]'),('ownershipPolicyID','s'),('initialMembershipRevision','u'),('nonce','b'),('issuedAt','u'),('expiresAt','u')]),
'ProposeMembershipIntent': ('propose-membership-v2',C+[('pairingID','s'),('expectedPairingRevision','u'),('pairReceiptHash','b'),('context','PairingContext')]),
'MembershipProposal': ('membership-proposal-v2',C+[('proposalID','s'),('pairingID','s'),('pairTranscriptHash','b'),('pairReceiptHash','b'),('context','PairingContext'),('authorizingOwner','OwnerDescriptor'),('candidate','OwnerDescriptor'),('resultingOwners','[OwnerDescriptor]'),('nextMembershipRevision','u'),('nonce','b'),('issuedAt','u'),('expiresAt','u')]),
'RootChallenge': ('root-challenge-v2',C+[('challengeID','s'),('requestID','s'),('deviceID','s'),('rootKeyEpoch','u'),('purpose','s'),('scopeID','s'),('payloadHash','b'),('sequence','u'),('issuedAt','u'),('expiresAt','u'),('nonce','b')]),
'RootProof': ('root-proof-v2',[('rootKind','s'),('challenge','RootChallenge'),('proof','b')]),
'OwnerSessionIntent': ('owner-session-v2',C+[('accountID','s'),('deviceID','s'),('rootKeyEpoch','u'),('clientRequestID','s'),('requestedScopes','[s]'),('requestedExpiresAt','u')]),
'ResultLookupIntent': ('result-lookup-v2',C+[('operationID','s'),('originalActorDeviceID','s'),('originalPurpose','s')]),
'OperationState': ('operation-state-v2',[('scopeKind','s'),('scopeID','s'),('revision','u'),('status','s'),('objectHash','b'),('approvedSignerIDs','[s]'),('phaseExpiresAt','u'),('receiptHash','?b')]),
'SignedState': ('authority-state-v2',C+[('scopeKind','s'),('scopeID','s'),('revision','u'),('payloadHash','b'),('issuedAt','u'),('expiresAt','u')]),
'ControlIntent': ('control-v2',C+[('scopeKind','s'),('scopeID','s'),('expectedRevision','u'),('operation','s'),('actorDeviceID','s')]),
'PairReceipt': ('pair-receipt-v2',[('transcript','PairTranscript'),('aConsentDigest','b'),('bConsentDigest','b'),('confirmedAt','u'),('expiresAt','u')]),
'AccountReceipt': ('account-receipt-v2',[('genesis','AccountGenesis'),('pairReceiptHash','b'),('aApprovalDigest','b'),('bApprovalDigest','b'),('createdAt','u'),('membershipRevision','u'),('ledgerFirstSequence','u'),('ledgerLastSequence','u'),('ledgerHeadHash','b')]),
'MembershipReceipt': ('membership-receipt-v2',[('proposal','MembershipProposal'),('authorizerApprovalDigest','b'),('candidateApprovalDigest','b'),('committedAt','u'),('membershipRevision','u'),('ledgerFirstSequence','u'),('ledgerLastSequence','u'),('ledgerHeadHash','b')]),
}
def sized(b): return struct.pack('>I',len(b))+b
def field(kind,value):
 if kind.startswith('?'): return b'\0' if value is None else b'\1'+field(kind[1:],value)
 if kind.startswith('['): return struct.pack('>Q',len(value))+b''.join(field(kind[1:-1],x) for x in value)
 if kind=='s': return sized(value.encode('utf-8'))
 if kind=='b': return sized(value)
 if kind=='u': return struct.pack('>Q',value)
 return sized(canonical(kind,value))
def canonical(kind,value):
 domain,fields=S[kind]
 return b'SwiftKey\0\1'+sized(domain.encode())+b''.join(field(t,value.get(n)) for n,t in fields)
def digest(kind,value):return hashlib.sha256(canonical(kind,value)).digest()
def wire(kind,value):
 if kind.startswith('?'):return None if value is None else wire(kind[1:],value)
 if kind.startswith('['):return [wire(kind[1:-1],x) for x in value]
 if kind=='u':return str(value)
 if kind=='b':return base64.b64encode(value).decode()
 if kind=='s':return value
 return {n:wire(t,value[n]) for n,t in S[kind][1] if n in value and value[n] is not None}
def uid(n):return f'00000000-0000-0000-0000-{n:012x}'
# Deliberately public full-width test scalars. Tiny imported scalar 9 exposes a
# host-provider verification disagreement recorded in artifacts/phone-v2; never weaken
# production verification to make a fixture pass.
def key(n):return ec.derive_private_key(int.from_bytes(bytes([0x33])*31+bytes([n]),'big'),ec.SECP256R1())
def pub(n):return key(n).public_key().public_bytes(serialization.Encoding.X962,serialization.PublicFormat.UncompressedPoint)
auth={'authorityID':hashlib.sha256(pub(9)).digest(),'origin':'https://swiftkey.example','audience':'swiftkey-authority-v2'}
root='android-strongbox-p256';policy='two-owner-survivor-v1';nonce=bytes(range(32));h=lambda x:hashlib.sha256(x.encode()).digest()
records=[]
def put(kind,value,name=None): records.append({'name':name or kind,'type':kind,'wire':wire(kind,value),'canonicalHex':canonical(kind,value).hex(),'sha256':digest(kind,value).hex()});return value
owners=[put('OwnerDescriptor',{'deviceID':uid(n),'rootKind':root,'rootKeyEpoch':n,'rootPublicKey':pub(n),'attestationReceiptHash':h('trust'+str(n)),'role':'owner'},'owner'+str(n)) for n in [1,2,3]]
a,b,c=owners
admission=put('PreEnrollmentChallenge',dict(auth,challengeID=uid(30),requestID=uid(40),deviceID=a['deviceID'],rootKind=root,trustPolicyID='test-android-strongbox-v1',nonce=nonce,issuedAt=1000,expiresAt=1900))
evidence=put('AttestationEvidence',dict(rootKind=root,certificates=[b'canonical vector only; not an attestation certificate']))
trust=put('DeviceTrustReceipt',dict(auth,deviceID=a['deviceID'],rootKind=root,rootKeyEpoch=1,rootPublicKey=pub(1),originalChallengeHash=digest('PreEnrollmentChallenge',admission),evidenceHash=digest('AttestationEvidence',evidence),trustPolicyID=admission['trustPolicyID'],verifiedAt=1050,leaseExpiresAt=1950))
roster=put('AccountRoster',dict(auth,accountID=uid(10),accountLabel='Café',ownershipPolicyID=policy,membershipRevision=1,owners=[a,b],issuedAt=1090,expiresAt=1150))
existing=put('ExistingAccountContext',dict(accountID=uid(10),accountLabel='Café',ownershipPolicyID=policy,membershipRevision=1,existingOwners=[a,b],lostOwner=b))
create=put('PairingContext',dict(purpose='createAccount'),'createContext');replace=put('PairingContext',dict(purpose='replaceOwner',existingAccount=existing),'replaceContext')
put('CreatePairingIntent',dict(auth,requestID=uid(41),initiator=a,context=create))
inspect=put('PairingInspection',dict(auth,pairingID=uid(20),revision=1,initiator=a,context=create,issuedAt=1100,expiresAt=1220))
put('JoinPairingIntent',dict(auth,pairingID=uid(20),expectedRevision=1,inspectionHash=digest('PairingInspection',inspect),initiatorHash=digest('OwnerDescriptor',a),candidate=b))
transcript=put('PairTranscript',dict(auth,pairingID=uid(20),revision=2,context=create,owners=[a,b],nonce=nonce,issuedAt=1100,expiresAt=1220))
def proof(owner,purpose,scope,kind,payload,n,issued=1110,expires=1200):
 challenge=dict(auth,challengeID=uid(100+n),requestID=uid(200+n),deviceID=owner['deviceID'],rootKeyEpoch=owner['rootKeyEpoch'],purpose=purpose,scopeID=scope,payloadHash=digest(kind,payload),sequence=5,issuedAt=issued,expiresAt=expires,nonce=nonce)
 put('RootChallenge',challenge,'challenge'+str(n))
 signed={'rootKind':root,'challenge':challenge,'proof':key(int(owner['deviceID'][-12:],16)).sign(canonical('RootChallenge',challenge),ec.ECDSA(hashes.SHA256()))}
 return put('RootProof',signed,'proof'+str(n))
p1=proof(a,'confirmPair',uid(20),'PairTranscript',transcript,1);p2=proof(b,'confirmPair',uid(20),'PairTranscript',transcript,2)
pair=put('PairReceipt',dict(transcript=transcript,aConsentDigest=digest('RootProof',p1),bConsentDigest=digest('RootProof',p2),confirmedAt=1120,expiresAt=1420))
put('ProposeAccountIntent',dict(auth,pairingID=uid(20),expectedRevision=3,pairReceiptHash=digest('PairReceipt',pair),label='Café',ownershipPolicyID=policy))
genesis=put('AccountGenesis',dict(auth,proposalID=uid(21),pairingID=uid(20),pairTranscriptHash=digest('PairTranscript',transcript),accountID=uid(10),label='Café',owners=[a,b],ownershipPolicyID=policy,initialMembershipRevision=1,nonce=nonce,issuedAt=1130,expiresAt=1420))
put('ReplaceGenesisIntent',dict(auth,pairingID=uid(20),expectedRevision=4,oldProposalHash=digest('AccountGenesis',genesis),newLabel='Café revised',newOwnershipPolicyID=policy))
put('RenewLeaseIntent',dict(auth,deviceID=a['deviceID'],rootKeyEpoch=1,existingTrustReceiptHash=digest('DeviceTrustReceipt',trust)))
p3=proof(a,'approveGenesis',uid(21),'AccountGenesis',genesis,3,1135,1255);p4=proof(b,'approveGenesis',uid(21),'AccountGenesis',genesis,4,1135,1255)
account=put('AccountReceipt',dict(genesis=genesis,pairReceiptHash=digest('PairReceipt',pair),aApprovalDigest=digest('RootProof',p3),bApprovalDigest=digest('RootProof',p4),createdAt=1140,membershipRevision=1,ledgerFirstSequence=1,ledgerLastSequence=4,ledgerHeadHash=h('ledger')))
mt=put('PairTranscript',dict(auth,pairingID=uid(22),revision=2,context=replace,owners=[a,c],nonce=nonce,issuedAt=1100,expiresAt=1220),'membershipTranscript')
p5=proof(a,'confirmPair',uid(22),'PairTranscript',mt,5);p6=proof(c,'confirmPair',uid(22),'PairTranscript',mt,6)
mpair=put('PairReceipt',dict(transcript=mt,aConsentDigest=digest('RootProof',p5),bConsentDigest=digest('RootProof',p6),confirmedAt=1120,expiresAt=1420),'membershipPairReceipt')
put('ProposeMembershipIntent',dict(auth,pairingID=uid(22),expectedPairingRevision=3,pairReceiptHash=digest('PairReceipt',mpair),context=replace))
mp=put('MembershipProposal',dict(auth,proposalID=uid(23),pairingID=uid(22),pairTranscriptHash=digest('PairTranscript',mt),pairReceiptHash=digest('PairReceipt',mpair),context=replace,authorizingOwner=a,candidate=c,resultingOwners=[a,c],nextMembershipRevision=2,nonce=nonce,issuedAt=1130,expiresAt=1420))
p7=proof(a,'approveMembership',uid(23),'MembershipProposal',mp,7,1135,1255);p8=proof(c,'approveMembership',uid(23),'MembershipProposal',mp,8,1135,1255)
put('MembershipReceipt',dict(proposal=mp,authorizerApprovalDigest=digest('RootProof',p7),candidateApprovalDigest=digest('RootProof',p8),committedAt=1140,membershipRevision=2,ledgerFirstSequence=5,ledgerLastSequence=8,ledgerHeadHash=h('membership-ledger')))
put('OwnerSessionIntent',dict(auth,accountID=uid(10),deviceID=a['deviceID'],rootKeyEpoch=1,clientRequestID=uid(42),requestedScopes=['account.read','epoch.issue'],requestedExpiresAt=2000))
put('ResultLookupIntent',dict(auth,operationID=uid(21),originalActorDeviceID=a['deviceID'],originalPurpose='approveGenesis'))
state=put('OperationState',dict(scopeKind='genesisProposal',scopeID=uid(21),revision=5,status='COMMITTED',objectHash=digest('AccountGenesis',genesis),approvedSignerIDs=[a['deviceID'],b['deviceID']],phaseExpiresAt=1420,receiptHash=digest('AccountReceipt',account)))
put('SignedState',dict(auth,scopeKind='genesisProposal',scopeID=uid(21),revision=5,payloadHash=digest('OperationState',state),issuedAt=1140,expiresAt=1200))
put('ControlIntent',dict(auth,scopeKind='pairing',scopeID=uid(20),expectedRevision=2,operation='cancel',actorDeviceID=a['deviceID']))
output={'generator':'Python struct/hashlib and cryptography; no Swift implementation used','authorityPublicKey':base64.b64encode(pub(9)).decode(),'vectors':records}
Path(__file__).with_name('pairing-v2-vectors.json').write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n')
print(f'{len(records)} vectors; {len(set(x["type"] for x in records))} record types')
