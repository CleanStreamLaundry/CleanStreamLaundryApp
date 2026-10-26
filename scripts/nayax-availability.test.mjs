import test from 'node:test';
import assert from 'node:assert/strict';
import { deriveAvailability, summarize, utcMillis } from '../supabase/functions/machine-availability/logic.ts';
const now = Date.parse('2026-09-28T21:00:00Z');
const event = (code, time='2026-09-28T20:59:00') => ({EventCode:code,EventDateTimeGMT:time,EventSourceName:'Device',EventGroupName:'Vending',EventCategoryName:'Vending'});
test('ground and release use the newest GMT event, regardless of response order',()=>{
  assert.equal(deriveAvailability([event(71,'2026-09-28T20:58:00'),event(70)],{MachineMQTTStatus:true},now).status,'busy');
  assert.equal(deriveAvailability([event(71),event(70,'2026-09-28T20:58:00')],{MachineMQTTStatus:true},now).status,'idle');
  assert.equal(utcMillis('2026-09-28T20:59:00'),Date.parse('2026-09-28T20:59:00Z'));
});
test('reused billing codes and missing source are never availability',()=>{
  assert.equal(deriveAvailability([{...event(71),EventSourceName:'Web - Engine',EventGroupName:'Billing'}],{MachineMQTTStatus:true},now).status,'unknown');
  assert.equal(deriveAvailability([{EventCode:71,EventDateTimeGMT:'2026-09-28T20:59:00'}],{MachineMQTTStatus:true},now).status,'unknown');
});
test('offline, future timestamps, reboot, and conflicting same-time events fail closed',()=>{
  assert.equal(deriveAvailability([event(71)],{MachineMQTTStatus:false},now).status,'unknown');
  assert.equal(deriveAvailability([event(71,'2026-09-28T22:00:00')],{MachineMQTTStatus:true},now).status,'unknown');
  assert.equal(deriveAvailability([event(71,'2026-09-28T20:58:00'),event(1)],{MachineMQTTStatus:true},now).status,'unknown');
  assert.equal(deriveAvailability([event(71),event(70)],{MachineMQTTStatus:true},now).status,'unknown');
  assert.equal(deriveAvailability([event(71)],{MachineMQTTStatus:true,LastPowerUpDateTime:'2026-09-28T20:59:30Z'},now).status,'unknown');
});
test('old idle events cannot restore readiness after a disconnect or newer event',()=>{
  assert.equal(deriveAvailability([event(71)],{MachineMQTTStatus:true},now,{reconcile_after:'2026-09-28T20:59:30Z'}).status,'unknown');
  assert.equal(deriveAvailability([event(71)],{MachineMQTTStatus:true},now,{event_at:'2026-09-28T20:59:30Z'}).status,'unknown');
  assert.equal(deriveAvailability([event(71)],{MachineMQTTStatus:true},now,{reconcile_after:'2026-09-28T20:58:30Z'}).status,'idle');
});
test('a VMC power-up invalidates older pulse state until a new device signal arrives',()=>{
  const powerUp = {...event(24,'2026-09-28T20:59:30'),EventDescription:'VMC Power Up Occured'};
  const stats = {MachineMQTTStatus:true,LastPowerUpDateTime:'2026-09-28T20:59:30'};
  for (const code of [70,71]) {
    assert.equal(deriveAvailability([event(code),powerUp],stats,now).reason,'awaiting_signal_after_restart');
    assert.equal(deriveAvailability([event(code,'2026-09-28T20:59:30'),powerUp],stats,now).status,'unknown');
    assert.equal(deriveAvailability([event(code,'2026-09-28T20:59:40'),powerUp],stats,now).status,code===70?'busy':'idle');
  }
  assert.equal(deriveAvailability([event(71),{...powerUp,EventSourceName:'Web - Engine'}],stats,now).status,'idle');
});
test('unknown/stale/unmapped machines never inflate available counts',()=>{
 const machines=[1,2,3,4].map(id=>({id,Machine_type:'Washer',Status:'idle'}));
 const states=[{machine_id:1,status:'idle',checked_at:'2026-09-28T20:59:55Z'},{machine_id:2,status:'busy',checked_at:'2026-09-28T20:59:55Z'},{machine_id:3,status:'idle',checked_at:'2026-09-28T20:58:00Z'}];
 assert.deepEqual(summarize(machines,states,now).washers,{total:4,available:1,busy:1,unknown:2});
});
