# ``SwiftyChain/KeychainError``

## Overview

`KeychainError` covers every failure mode you might encounter when
interacting with the keychain, on every platform. Pattern-match on specific
cases to provide targeted recovery.

Use ``Keychain/upsert(_:for:)`` to add or update. It first attempts add, then updates
a duplicate; the two steps are not a cross-platform atomic transaction.

Handle ``interactionNotAllowed`` when storage is locked or interaction cannot occur,
``userCanceled`` when the user dismisses authentication, and ``invalidArgument(_:)`` when
options conflict. Authentication failure is reported separately. On Linux, cancellation
from the operation timer is ``timedOut``.

`operationFailed(Int32)` retains the platform's code: `OSStatus` on Apple, libsecret or GLib
codes on Linux. Linux error domains are recorded in logs; identical codes can have different
meanings in different domains. See <doc:Linux> and <doc:MigratingTo2>.

## Topics

### Cases

- ``itemNotFound``
- ``duplicateItem``
- ``authenticationFailed``
- ``interactionNotAllowed``
- ``userCanceled``
- ``invalidArgument(_:)``
- ``unexpectedData``
- ``encodingFailed(_:)``
- ``decodingFailed(_:)``
- ``operationFailed(_:)``
- ``accessGroupDenied``
- ``platformUnsupported(_:)``
- ``timedOut``

### Platform Differences

On Linux, ``platformUnsupported(_:)`` also reports a missing libsecret, D-Bus session,
or Secret Service provider, and options Linux can't honor such as synchronizable items.
``timedOut`` is thrown after 30 seconds without a response. See <doc:Linux>.
