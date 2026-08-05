# CFFwelding V3.7 Phase 11–15 Design

**Date:** 2026-08-05

**Branch:** `codex/cffwelding-greenfield-v3.3`

**Baseline:** `a807a2d9226bd07d34d65d3cd313629da3905f60`

**Status:** implementation design baseline; written-spec review required before planning

## 1. Purpose and authority

This design defines how the repository advances from the completed Phase 10 offline source boundary through Phase 11, Phase 11A–11D, Phase 12, Phase 13, Phase 14, and Phase 15.

The authority order is:

1. `FINAL_DECISION_REGISTER.md`;
2. V3.7 implementation and final-review documents under `Docs/06_Codex实施`;
3. the relevant architecture, process, control, ADS, calibration, and report documents;
4. earlier code and tests, which must be migrated when they enforce superseded boundaries.

The implementation target is the V3.7 offline delivery boundary. It includes complete PLC source contracts, deterministic safe behavior, offline tests, TwinCAT XAE builds, reports, commits, and pushes. It does not claim runtime commissioning, real PDO mapping, drive or sensor calibration, hardware behavior, welding qualification, or production release.

`GVL_Status.bProductionReady` remains `FALSE`. Unknown hardware facts remain invalid or unconfirmed; they are never replaced with guessed values.

## 2. Selected approach

### 2.1 Options considered

- **Dependency-first packages (selected):** build process monitoring, hardware boundaries, control, recipe/peripherals, ADS, and final verification as independently testable packages.
- **Strict numeric implementation:** implement 11A, 11B, 11C, then 11D literally. This would create interim actuator and mapping structures that later V3.7 decisions replace.
- **Monolithic Phase 11–14 change:** implement all remaining source at once. This makes TwinCAT XML, ownership, and regression failures difficult to isolate.

### 2.2 Package order

The selected order is:

1. Phase 11 process monitoring and result production;
2. Phase 11A external interface contracts;
3. Phase 11B collision replacement and peripheral module contracts;
4. Phase 11D final Legacy layout and unified actuator foundation;
5. Phase 11C module Actions, IO configuration, transport, and Maintenance integration;
6. Phase 12 mode, command, initialization, Maintenance, and machine state;
7. Phase 13 Program, JoiningPoint, Robot, peripherals, alarm, and tower light;
8. Phase 14 ADS and traceability contract;
9. Phase 15 full verification and delivery.

The acceptance labels and reports remain Phase 11A–11D. Only the internal construction order changes so that Phase 11C consumes the final Phase 11D actuator model instead of creating obsolete single- and double-solenoid FBs.

## 3. Cross-cutting architecture

The remaining implementation is divided into six bounded subsystems:

1. **Process data plane:** frozen process inputs, engineering conversion, features, quality observation, curve recording, and immutable result candidates.
2. **Hardware abstraction plane:** Raw process images, IO configuration, typed adapters, normalized module interfaces, and module-owned physical outputs.
3. **Control plane:** authoritative mode/source, command arbitration, initialization, Maintenance, permissions, and machine state.
4. **Recipe and peripheral plane:** Program revisions, JoiningPoint resolution, cycle snapshots, Robot and fastener coordination, alarms, and tower lights.
5. **ADS and traceability plane:** packed public DTOs, version contract, coherent snapshots, command status, paging, and final result ownership.
6. **Verification plane:** static contracts, numerical/state-machine tests, TwinCAT build evidence, reports, and Git/remote checks.

The following invariants apply everywhere:

- only axis adapters access `AXIS_REF` or instantiate MC FBs;
- Fast programs read accepted immutable snapshots, not mutable live configuration;
- every command, state, physical output, handshake flag, alarm slot, curve buffer, and result record has one writer;
- cross-task transfer uses Request/Ack or a coherent Sequence protocol;
- invalid data is carried with a reason and cannot become an implicit zero-valued PASS;
- unconfirmed mapping, calibration, layout, direction, or feedback remains fail closed.

## 4. Phase 11 process monitoring

### 4.1 Frozen input boundary

The cycle snapshot is extended to include the accepted R-axis profile, process monitor profile, torque engineering configuration, observer configuration, process-window configuration, and their IDs/revisions. The producer holds the snapshot stable until Fast acknowledges it. `PRG_FastMonitoring` uses only this accepted snapshot for the active cycle.

### 4.2 Torque engineering validity

Raw drive torque and engineering torque are separate values. The engineering configuration contains scale, offset, direction, revision, and explicit confirmation. Engineering torque is valid only when:

- the drive status source is valid;
- every required conversion field is finite and in range;
- the revision is nonzero and matches the frozen snapshot;
- the configuration is explicitly confirmed.

When invalid, the engineering torque payload is set to `0.0` for deterministic transport while `bTorqueEngineeringValid` is `FALSE`; consumers must gate on validity, and Power, Energy, torque-derived Observer channels, torque windows, and formal quality results remain invalid. Drive linkage alone never proves Nm.

### 4.3 Power and energy

The diagnostic signed power is:

```text
PowerSigned_W = Torque_Nm * 2 * PI * RPM / 60
```

Gross and Qualified Energy integrate `ABS(PowerSigned_W)` so direction changes cannot cancel physical input energy.

- Gross Energy starts at the earlier valid event of accepted Contact or actual R rotation and runs through cycle completion, including braking.
- Qualified Energy integrates only while Contact is valid, actual RPM direction agrees with the frozen target, `ABS(RPM)` meets the frozen minimum, Force meets a distinct frozen `MinimumQualifiedForce`, braking is false, torque engineering is valid, and the sample period is valid.
- reset, overflow, non-finite inputs, invalid sample time, and state discontinuity produce explicit validity/reason outputs.

### 4.4 Step statistics

`FB_ForceStepStatistics` and supporting typed records publish per-step:

- Force mean/min/max/RMS, Force error RMS, and time-in-band ratio;
- Torque mean/min/max and maximum absolute rate;
- RPM mean/min/max;
- SRel start/end and peak absolute rate;
- Gross and Qualified Energy deltas;
- elapsed time, Qualified Hold, sample count, validity, and EndCause.

Phase-specific features include Step 1 arrival timing, initial torque peak, and acceleration energy; Step 2 steady-state statistics; Step 3 torque/rate peaks, Force extrema, SRel rate peak, energy, RPM drop, and EndCause; and Brake time, reversal/peak, stopped timestamp, and Force-ramp timestamp.

### 4.5 Material Interface Observer

`FB_MaterialInterfaceObserver` is monitor-only. It consumes valid Force, Force error, Torque, Torque residual, torque rate, SRel, SRel rate, RPM, and Z velocity plus a frozen observation window. Its configuration explicitly enables individual criteria, defines each criterion's comparison direction and finite threshold, defines `nMinimumVotes`, and defines a continuous confirmation time. Candidate is true only inside the observation window when at least `nMinimumVotes` enabled criteria pass. Confirmed rises after Candidate remains continuously true for the confirmation time. Confidence is the percentage of enabled criteria that pass, clamped to 0–100%. If an enabled criterion lacks a valid input, the Observer result is invalid; disabled torque criteria permit a force/SRel-only offline vector. Invalid configuration, zero enabled criteria, or insufficient valid channels yields no Candidate or Confirmed event.

The outputs are Candidate, Confirmed, Confidence, EventSRel, EventForce, EventTorque, timestamp, validity, and reason. No Observer output is connected to sequence transitions, axis commands, safety decisions, or actuator commands.

### 4.6 Process Window

`FB_ProcessWindowMonitor` evaluates frozen step and whole-cycle limits with explicit input validity. Minimum and maximum acceptance limits are inclusive. A value outside an enabled warning boundary but inside the NOK boundary produces WARNING; a value at or beyond an enabled NOK boundary produces NOK. Each enabled boundary has a nonnegative release hysteresis. WARNING and NOK reason bits latch until the cycle reset, while the live state may return only after re-entering the corresponding boundary by its hysteresis. Missing required input or invalid/revision-mismatched configuration produces INVALID, which cannot be converted to PASS. The monitor never directly changes motion or step progression.

### 4.7 Curve recorder

The recorder owns two fixed buffers of 4096 `ST_CurveSample` records each.

- exactly one available buffer may be active;
- cycle end freezes the active buffer, assigns BufferId and Revision, and exposes SampleCount/SamplePeriod/Truncated/Incomplete/Overrun;
- an unconsumed frozen buffer is never overwritten;
- if both buffers are unavailable, recording is rejected and the result is marked Overrun/Incomplete;
- if a cycle exceeds 4096 samples, recording stops at the boundary and sets Truncated; there is no silent decimation;
- Slow acknowledges consumption with the exact BufferId and Revision only after result publication and all requested pages for that frozen revision are complete or explicitly abandoned; a mismatched acknowledgement has no effect;
- curve arrays remain internal and are not exposed as direct ADS notification targets.

### 4.8 Result ownership

`PRG_FastMonitoring` owns the monitoring FB instances and writes one immutable `FastResultCandidate` mailbox with RequestId and Revision. `PRG_ResultTraceability` acknowledges the candidate, allocates WeldId, and is the only writer of the final cycle-result record. Fast and Slow never partially write the same result structure.

## 5. Phase 11A–11D external and actuator boundary

### 5.1 Final `GVL_IO`

The final direct interface is exactly:

- `Z_axis` and `R_axis`;
- `nZForceRaw`, `nZDisplacementRaw`;
- `bModeManualSwitch`, `bModeAutomaticSwitch`, `bModeMaintenanceSwitch`;
- `bControlLocalSwitch`, `bControlRobotSwitch`;
- `qLampRed`, `qLampYellow`, `qLampGreen`;
- internal clean `bZHomeSwitch`, `bZLimitPositiveSwitch`, `bZLimitNegativeSwitch` without `AT`.

The three clean Z signals are written from `gunBOX_bullIn` only through `PRG_IO_Config`. Old direct Collision, Clamp, Feeder, Robot, and lamp aliases are removed. `PRG_ClampControl` is removed from source, project includes, task calls, tests, and reports.

### 5.2 Legacy Raw boundary

`GVL_ExternalIO` preserves the exact external names:

- `robot_to_plc`, `plc_to_robot`;
- `bsensor`, `bactuaor`;
- `SMCBOX_bullfOut`, `SMCBOX_bullfIn`, `SMCBOX_portDo`;
- `gunBOX_bullIn`, `gunBOX_byteIn`.

The Legacy type names and field spellings, including `ST_actuaor`, `Ousint`, `OUT_BOOL_TO_USINT`, and `passsingal`, are preserved. `DUT_USINT` and `ST_USINT` must be exactly one byte as proven by runtime layout checks and generated TMC evidence.

`PRG_IO_Config` is the only Raw reader/writer. Its public Actions, in the frozen naming, are:

- `ACT_ClearInputSnapshots`;
- `ACT_ReadRobotRaw`;
- `ACT_ReadStationSensorStruct`;
- `ACT_ReadSmcBoxBits`;
- `ACT_ReadGunBoxBoolBits`;
- `ACT_ReadGunBoxByteInputs`;
- `ACT_ClearRawOutputs`;
- `ACT_WriteActuatorStruct`;
- `ACT_WriteSmcBoxOutputs`;
- `ACT_WriteRobotRaw`;
- `ACT_ValidateRawLayouts`;
- `ACT_UpdateMappingValidity`.

`ACT_ReadRawInputs` and `ACT_WriteRawOutputs` are orchestration names used by the implementation plan, not additional TwinCAT Actions: the former means the ordered six input Actions and the latter means the ordered four output Actions above.

Raw outputs are cleared first on every scan and only confirmed fields are then encoded. Unused bits stay zero. No module or coordinator accesses `GVL_ExternalIO`.

The Main-task order is fixed as: IO_Config input Actions; Mode; Robot; Command; Program; Initialize; Calibration; Maintenance; Manual/Auto; Fastener Transport Coordinator; GunHeadFeed; Magazine; FastenerStation; MachineMain; Alarm; TowerLight; IO_Config output Actions. Input snapshots therefore exist before any consumer runs, and physical outputs are committed only after every owner and interlock has run.

### 5.3 Typed bus and module contracts

Robot Profinet, Feeder/GunHead EtherCAT, and the three peripheral modules receive dedicated packed Raw types, typed GVL snapshots, adapters, normalized Request/Status/Config/State types, and PROGRAM owners. Typed bus GVLs are internal snapshots/contracts; they do not create a second Raw/PDO owner.

Module counts are frozen as:

- GunHeadFeed: 3 inputs and 2 outputs;
- Magazine: 8 inputs and 5 outputs;
- FastenerStation: 10 inputs and 7 outputs.

Phase 11B functional behavior treats FastenerStation as input-only. Phase 11D declares the final seven outputs—pull-pin cylinder, reduced-pressure feed air, normal feed air, vibrator, triple air, track-head air, and bin-door cylinder—but they stay safe until their definitions and mappings are confirmed.

### 5.4 Collision displacement teach

All old Collision digital and bus fields are deleted. `PRG_ServiceCalibration` uniquely owns `FB_CollisionDisplacementTeach`.

An accepted external-displacement calibration window latches the external displacement and NC axis position in the same scan. N repeated samples produce separate means and ranges for both references, sample count, Revision, validity, and rejection reason. Runtime processing uniquely owned by `PRG_FastInputs` publishes:

- `CollisionDistanceSensor` as the primary remaining distance;
- `CollisionDistanceAxis` as NC redundancy;
- `CollisionMismatch`, plausibility, validity, and reason.

The result stays invalid until sample count, range, reference, direction, sensor, and NC prerequisites pass. No Collision input or Collision bus field is retained.

### 5.5 Coordinator and handshake

The final coordinator name is `PRG_FastenerTransportCoordinator`. The later and more specific D-080 rule resolves the earlier D-072 naming. No duplicate Supply coordinator is created.

The coordinator routes only transport mode, module Requests, Status, and the fixed handshake:

- the upstream module uniquely writes `bFastenerReadyToSend`;
- the downstream module uniquely writes `bReadyToReceive`;
- only the upstream starts a transfer after both are true.

It supports Station→Magazine→GunHeadFeed→GunHead and Station→GunHeadFeed→GunHead. It never writes valves or FB commands.

### 5.6 Unified actuator

Only `FB_Actuator` is used for single- and double-solenoid cylinders. `ST_ActuatorConfig.bDoubleSolenoid` selects behavior. The FB has no GVL dependency, does not modify inputs, and provides deterministic safe idle, mutual exclusion/dead time, filtered feedback, movement timeout, fault latch, Reset, Stop, and one-scan Done.

There are exactly six instances:

- GunHeadFeed: detection cylinder;
- Magazine: three-position cylinder and two full-check cylinders;
- FastenerStation: pull-pin cylinder and bin-door cylinder.

Each instance is declared, called, and commanded only by its module PROGRAM. Timed air uses `FB_TimedAirValve`.

Every module PROGRAM contains exactly these public Actions in order: `ACT_ResetTransient`, `ACT_EvaluateInputs`, `ACT_UpdateHandshake`, `ACT_Automatic_TODO`, `ACT_MaintenanceJog`, `ACT_ApplyInterlocks`, `ACT_UpdateStatus`, `ACT_RaiseAlarms`, and `ACT_CommitOutputs`.

Module command priority is Fault/Stop, then valid Maintenance Hold, then confirmed Automatic, then safe idle. `ACT_Automatic_TODO` reports automatic logic as unconfigured and writes safe outputs only. No guessed automatic feeding sequence is implemented.

Maintenance follows:

```text
ADS Hold/Heartbeat
→ PRG_MaintenanceControl
→ module Maintenance Request
→ module ACT_MaintenanceJog
→ final E_ActuatorCommand
→ FB_Actuator / FB_TimedAirValve
→ module physical output
→ PRG_IO_Config
→ Raw output
```

Release, session change, heartbeat timeout, mode change, Stop, or Fault cancels the command.

## 6. Phase 12 control plane

### 6.1 Mode and source

The only legal combinations are:

- Maintenance + Local;
- Manual + Local;
- Automatic + Robot.

Hardware switches are authoritative and WPF is read-only. Invalid combinations are not coerced. A mode/source change during operation requests Controlled Stop, records `MODE_CHANGED_DURING_OPERATION`, and is reevaluated only after stop completion.

### 6.2 Command contracts and dispatcher

HMI and Robot use separate complete request/status mailboxes. HMI requests include CommandId, ClientSessionId, CommandCode, SubCommand, ObjectId, PayloadRevision, and typed parameters. Robot uses its frozen Sequence/Ack contract.

`PRG_CommandDispatcher` owns deduplication, permission evaluation, request acceptance, Ack/Active/Completed tracking, reject reasons, and one-scan internal pulses. It never clears producer request fields.

Priority is:

1. Fault/safety gate;
2. Stop/Abort;
3. Reset;
4. Initialize;
5. Maintenance Hold;
6. Start.

Manual Start is local HMI only. Automatic Start is a new Robot Sequence only. Maintenance Execute runs only an already selected and permitted function. Stale, duplicate, zero, malformed, or unauthorized requests do not produce internal pulses.

### 6.3 Machine, Initialize, Reset, and Maintenance

`PRG_MachineMain` is the only Machine State writer. It coordinates BOOT, STOPPED, INITIALIZING, READY, STARTING, RUNNING, MAINTENANCE_ACTIVE, CONTROLLED_STOPPING, CYCLE_COMPLETE, RESETTING, and FAULT through typed request/status interfaces.

Initialize implements the specified deterministic substates from transient clearing through communication/sensor validation, safe axis/peripheral operations, calibration/program validation, and final Ready evaluation. Hardware-dependent steps fail closed when their prerequisites are unconfirmed.

Stop performs application-level controlled unloading and records an active cycle as Abort/NOK. It is not a safety stop. Reset clears only permitted latches after source conditions disappear; it does not restart a cycle, delete history, or imply Start.

Maintenance selection and Hold-to-Run are owned by `PRG_MaintenanceControl`. Hold binds ClientSessionId, heartbeat, target, action, enable, and setpoint to the active mode and permission state.

## 7. Phase 13 Program and peripherals

### 7.1 Program lifecycle

The lifecycle is:

```text
Edit Buffer → Validate → Draft → Activate → Active
```

Save and Activate use RequestId/Ack plus Expected/Actual Revision. A stale expected revision is rejected. Only `PRG_ProgramManager` writes Active Programs.

JoiningPointNo uniquely resolves one valid Active Program. Start acceptance atomically copies JoiningPoint, Program, Machine/Limits, Z/R profiles, Monitor profile, Torque configuration, and required revisions into an immutable Cycle Snapshot. The producer holds the snapshot until Fast Ack.

The final capacities are 128 Programs and 256 JoiningPoints, matching the Program specification. The current 64/512 constants are an interim Phase 10 allocation and are migrated with an explicit generated-memory budget.

### 7.2 Robot and peripheral control

Robot input decoding requires a confirmed 20-byte layout and valid heartbeat/sequence. Until confirmation, the adapter does not decode Start, does not generate a false Ack, and keeps Auto Ready false.

The transport coordinator uses only normalized module contracts. Module timeouts and failures produce typed status/reasons for MachineMain and AlarmControl; they do not bypass ownership.

### 7.3 Alarm and tower light

Alarm producers own fixed request slots. `PRG_AlarmControl` aggregates, latches, acknowledges only after source review, stores history, and serves pages. Producers never write global alarm history.

`PRG_TowerLightControl` is the only writer of the three lamp outputs. The frozen priority is Fault, Maintenance, Running, Ready, then Stopped, including deterministic blink timing.

## 8. Phase 14 ADS and traceability

### 8.1 Public contract

`GVL_HMI` uses `qualified_only` and is the only supported WPF access surface. Public DTOs use `pack_mode := 1`; internal objects use `TcNoSymbol` where this does not hide required Persistent data.

The contract publishes Magic, InterfaceMajor, InterfaceMinor, SchemaCrc, PlcBuild, BootId, AdsPort, and task periods. SchemaCrc is a checked-in constant generated from the ordered public DTO schema and is changed whenever binary layout changes. BootId is a retained monotonically increasing counter advanced once during cold-start initialization, so a client can distinguish reconnect from PLC restart. A client with a contract mismatch is diagnostic/read-only and cannot issue control requests.

### 8.2 Command and status

The client writes a complete command request atomically. PLC never clears it and publishes AckCommandId, ActiveCommandId, CompletedCommandId, ExecutionState, RejectReason, MachineState, and ResultRevision.

Status publication uses a seqlock-style odd/even Sequence protocol. Slow marks the sequence odd, copies a private coherent snapshot, and then publishes equal even SequenceStart/SequenceEnd values. A client accepts data only when both values match and are even.

### 8.3 Transfer and paging

- Maintenance Hold binds ClientSessionId and heartbeat and is cancelled on disconnect semantics.
- Program and JoiningPoint transfer use Request/Ack and Expected/Actual Revision.
- Alarm pages return at most 32 records.
- Curve pages return at most 256 samples from one frozen BufferId/Revision.
- Result snapshots publish WeldId, point/program revisions, result/reasons, step end causes, features, energy, final SRel, time, and curve metadata.

Notifications are limited to StatusRevision, CommandAckId, AlarmRevision, ResultRevision, CurveReadyRevision, and PlcHeartbeat. A notification causes the client to read the full structure or requested page. There is no per-sample notification.

Application Stop is an ADS command. The contract and reports explicitly prohibit using ADS control state to stop the PLC Runtime.

## 9. Error handling

All public and cross-task interfaces carry explicit validity and reason information.

- unknown commands, illegal mode/source, stale revisions, invalid snapshots, duplicate IDs, and unauthorized sources are rejected without side effects;
- invalid Torque, sensor, monitor, curve, or result inputs cannot generate a PASS result;
- output layouts are clear-first and remain zero while unconfirmed;
- Robot decode, module Automatic, and production readiness remain disabled while their contracts are unconfirmed;
- curve exhaustion is reported as Overrun/Incomplete and never overwrites unconsumed data;
- session changes and heartbeat timeouts revoke Maintenance commands;
- runtime/hardware facts are reported as unverified, not inferred from successful compilation.

## 10. Testing and verification

Each package follows test-driven implementation: add a failing contract or reference-vector test, confirm the expected failure, implement the complete package behavior, then run focused and full regression.

The test set covers:

- XML includes, GUID uniqueness, task-call order, single instance, and one-writer ownership;
- numerical vectors, zero/negative limits, non-finite inputs, reset, saturation, integration gates, and step statistics;
- Observer monitor-only isolation and Process Window boundaries/hysteresis/latching;
- curve BufferId/Revision/freeze/consume/truncate/overrun behavior at 4096 boundaries;
- Collision same-scan latch, N-sample means/ranges, reject paths, and runtime mismatch;
- exact Legacy names, packed sizes, one-byte union layout, Raw access whitelist, and clear-first outputs;
- `FB_Actuator` single/double behavior, mutual exclusion, dead time, feedback filtering, timeout, Done, Stop, Reset, and fault latch;
- six actuator instances, owners, Maintenance release/heartbeat, module Actions, and transfer handshake;
- mode/source matrix, command permission/deduplication, state transitions, Initialize, Stop, and Reset;
- Program revision conflicts, JoiningPoint uniqueness, immutable snapshot handshake, Robot fail-closed behavior, alarms, and lamp priority;
- ADS pack layout, contract versioning, seqlock status, command status, pages, and Revision notifications.

The package entry scripts are:

- `scripts/Test-Phase11ProcessMonitoring.ps1`;
- `scripts/Test-Phase11AExternalInterfaces.ps1`;
- `scripts/Test-Phase11BCollisionAndModules.ps1`;
- `scripts/Test-Phase11DLegacyAndActuator.ps1`;
- `scripts/Test-Phase11CModuleIntegration.ps1`;
- `scripts/Test-Phase12MainControl.ps1`;
- `scripts/Test-Phase13ProgramAndPeripherals.ps1`;
- `scripts/Test-Phase14AdsAndTraceability.ps1`;
- `scripts/Test-Phase15FinalAcceptance.ps1`.

These scripts validate their named package rather than merely checking that a file or symbol exists. They include negative vectors and inspect the implementation paths that prove the claimed behavior.

After every package:

1. run the focused new test;
2. run all applicable Phase 1–10 regressions and migrate tests that encode superseded Collision, Clamp, GVL_IO, or actuator boundaries;
3. run the standard TwinCAT Release x64 offline build;
4. inspect generated TMC/layout and memory evidence after Phase 11, Phase 11D, Phase 14, and the final Phase 15 build;
5. update execution, ownership, interface, build, and Git reports;
6. commit intentionally and push the current branch;
7. verify local/remote commit identity without exposing credentials.

Phase 15 performs a requirement-by-requirement audit rather than relying only on test names or a green build.

### 10.1 Required report artifacts

The implementation creates or updates, as applicable:

- `PHASE_11_EXECUTION_REPORT.md`, `PHASE_11A_EXECUTION_REPORT.md`, `PHASE_11B_EXECUTION_REPORT.md`, `PHASE_11D_EXECUTION_REPORT.md`, `PHASE_11C_EXECUTION_REPORT.md`, `PHASE_12_EXECUTION_REPORT.md`, `PHASE_13_EXECUTION_REPORT.md`, `PHASE_14_EXECUTION_REPORT.md`, and `PHASE_15_EXECUTION_REPORT.md`;
- `DIRECT_IO_CATALOG.md`, `BUS_INTERFACE_CATALOG.md`, and `COMMUNICATION_MANUAL_MAPPING_CHECKLIST.md`;
- `COLLISION_DISPLACEMENT_CALIBRATION_REPORT.md`, `PERIPHERAL_MODULE_INTERFACE_CATALOG.md`, and `ONE_WRITER_MATRIX.md`;
- `IO_CONFIG_MAPPING_MATRIX.md`, `MODULE_PROGRAM_ACTION_CATALOG.md`, `CYLINDER_INSTANCE_CATALOG.md`, and `FASTENER_TRANSFER_HANDSHAKE_MATRIX.md`;
- `ACTUATOR_INSTANCE_MATRIX.md`, `RAW_EXTERNAL_INTERFACE_CATALOG.md`, and `IO_CONFIG_ASSIGNMENT_REVIEW.md`;
- `ADS_STRUCT_LAYOUT.md`, `HARDWARE_TODO.md`, `COMMISSIONING_CHECKLIST.md`, and `IMPLEMENTATION_REPORT_CFFwelding_FINAL.md`;
- the existing `INSTANCE_OWNERSHIP_MATRIX.md`, `INTERNAL_INTERFACE_CATALOG.md`, `TWINCAT_BUILD_REPORT.md`, `GIT_EXECUTION_REPORT.md`, and hardware/manual-binding checklists.

Templates are copied into `Docs/报告` only when populated with current evidence. Empty templates are not completion evidence.

## 11. Conflict resolutions

| Conflict | Resolution |
|---|---|
| `PRG_FastenerSupplyCoordinator` vs `PRG_FastenerTransportCoordinator` | Use only the later, more specific D-080 `PRG_FastenerTransportCoordinator`. |
| FastenerStation 10 inputs/no outputs vs 10 inputs/7 outputs | Phase 11B behavior is input-only; final Phase 11D contract declares seven safe-disabled outputs per D-070/D-071. |
| `ACT_ValidateMappings` vs `ACT_ValidateRawLayouts` | Public Action is `ACT_ValidateRawLayouts`; any helper remains private. |
| GunHead Collision field vs no Collision IO/bus | Delete all Collision IO/bus fields under D-065/D-074; use external displacement plus NC redundancy. |
| two cylinder FBs vs unified FB | D-090–D-093 supersede the earlier wording; use only `FB_Actuator`. |
| report aliases `aRobotToPlc/aPlcToRobot` vs Legacy names | Use exact external names `robot_to_plc/plc_to_robot`. |
| old `PRG_ClampControl` tests vs final architecture | Remove the PROGRAM and migrate the tests under D-062 and V3.7 Phase 11A. |
| final-review document title says V3.2 inside a V3.7 file | The repository filename, V3.7 implementation plan, and final decision register define the V3.7 acceptance baseline. |
| current 64 Programs/512 JoiningPoints vs Program specification 128/256 | Migrate to 128 Programs and 256 JoiningPoints and record the generated memory change. |

## 12. Repository and safety boundary

- Work remains on `codex/cffwelding-greenfield-v3.3`, the branch explicitly selected by the user.
- Git identity remains repository-local.
- Passwords, PATs, tokens, and credential output are never read or recorded.
- No Scan, Activate Configuration, Download, Login, Online Change, real motion, or real output operation is authorized.
- `CFFwelding.project.~u` is not read, deleted, staged, or committed. The implementation adds a narrow repository ignore rule for `*.project.~u` to prevent future accidental staging while preserving the file.
- Generated `_Boot`, `_CompileInfo`, backup, and scratch artifacts remain excluded unless a V3.7 report explicitly requires a derived hash or layout fact.

## 13. Completion criteria

V3.7 offline delivery is complete only when every Phase 11–15 source requirement and named artifact has direct evidence, all applicable tests and the standard XAE build pass on the final source, required reports and matrices are current, tracked worktree changes are committed, branch and remote match, and remaining runtime/hardware/qualification gates are explicitly listed as unverified with `bProductionReady = FALSE`.

This design is an umbrella boundary. Implementation plans are created and executed package by package, beginning with Phase 11, so each package can be reviewed, built, committed, and verified before the next one starts.
