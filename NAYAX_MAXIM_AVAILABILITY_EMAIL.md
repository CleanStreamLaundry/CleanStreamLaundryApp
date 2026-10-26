# Nayax reply preparation — sent October 6; reviewed October 14

Status updated October 14, 2026. **The user sent the request on October 6; it is no longer an unsent draft.** The sent message is visible at 3:06 PM in Lynx case 03713828. The text below preserves the preparation copy, not a verbatim export of the user's final message. Yael's October 8 reply confirms Production Lynx permissions and explains Pulse feedback and Last Sales' dependency on our SaleEnd response. Exact Cortina callback authentication remains unanswered in case 03401910. See the [current findings](NAYAX_AVAILABILITY_RESEARCH.md#current-result--october-14); do not resend the answered questions. No credentials included.

Hi Yael and Maxim,

The QA registration issue is resolved, and our Lynx connection checks are now successful. Thank you for your help getting us set up.

We created a QA Lynx token under JacobKing and received HTTP 200 from status, lastAlerts and lastSales for test machine 1003684111. The sample machine is offline and returns empty alert and sales lists, so we are ready to continue testing with our physical reader.

Are you able to enable the required Lynx read permissions on our existing account, Clean Stream Laundry Solutions - DEV, for device lookup, machine status, lastAlerts and lastSales? The existing token reference is CleanStream machine availability. Our reader is 4434331126150568, machine ID 79835724. Our latest stored status/alerts check, from October 3, returned “Insufficient permissions to perform this action.”

For the related Cortina setup in case 03401910, Maxim mentioned that username/password authentication can be added to the incoming Sale, SaleEnd and Void requests. We found that our callback handler requires authentication while that shared configuration is currently missing. It presently supports x-nayax-auth or an Authorization bearer token. Are you able to configure either of those, or confirm the exact header names and encoding used by your username/password option? If we can configure it ourselves in Core, could you point us to that setting? We can then match our handler to the supported method and exchange credentials through your secure process.

One related bench-test question: for our pulse-configured reader, what specifically triggers SaleEndNotification—completion of the reader’s pulse output, or a separate confirmation from the machine? Should Sale and SaleEndNotification still arrive when the reader is powered and online but not connected to a machine? This will help us interpret the callbacks correctly in the app.

We have the documentation for the reporting delivery options and will verify the transaction-source fields with our own reader data once access is enabled.

Thank you,
Jacob

## Follow-up preparation — October 14

**Prepared in Outlook; not sent.** Reply in Cortina case 03401910 to Professional Service, with existing Kevin, Alex and Maxim CCs retained. Per the owner’s correction, this draft asks only about Cortina callback authentication. Lynx permissions belong with Yael in case 03713828. No credentials are included; the original signature is preserved in Outlook.

Screenshot and body: `../.campaign-work/lynx-live-20261014/maxim-draft.jpg` and `maxim-draft-body.txt`.

Hi Maxim,

The earlier sandbox payment tests were successful, and we are working through the remaining setup before continuing with the physical reader.

For Cortina callback authentication, you mentioned that username/password headers can be configured at the operator level. We are happy to use whichever supported method is easiest for your team.

Are you able to configure that option for the Sale, SaleEnd and Void callbacks and confirm the exact header names and format? We can adjust our backend to match. It already supports x-nayax-auth or an Authorization bearer token if either is simpler.

Once the method is confirmed, we can exchange the matching credentials through your secure process.

Thank you,
