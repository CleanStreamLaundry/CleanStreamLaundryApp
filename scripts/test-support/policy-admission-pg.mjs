import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, chmod, lstat, realpath, rm, access, cp, symlink } from 'node:fs/promises';
import { isAbsolute, join, dirname } from 'node:path';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';

// Shared disposable PostgreSQL harness. No inherited database/cloud
// settings, network listeners, existing-database mode, or import-time startup.
async function command(file, args, env, timeout = 20000) {
  const child = spawn(file, args, { env, stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '', stderr = '';
  child.stdout.on('data', (part) => { stdout += part; });
  child.stderr.on('data', (part) => { stderr += part; });
  const timer = setTimeout(() => child.kill('SIGKILL'), timeout);
  try {
    await new Promise((resolve, reject) => {
      child.on('error', reject);
      child.on('close', (code) => code === 0 ? resolve() : reject(new Error(`${file}: ${code}\n${stderr}`)));
    });
    return stdout.trim();
  } finally { clearTimeout(timer); }
}

class Session {
  constructor(cluster) {
    this.child = spawn(join(cluster.bin, 'psql'), [
      '-X', '-A', '-t', '-q', '--no-password', '-v', 'ON_ERROR_STOP=1',
      '-v', 'VERBOSITY=verbose', '-h', cluster.socket, '-p', '55432',
      '-U', 'policy_fixture', '-d', 'loyalty_policy_fixture',
    ], { env: cluster.env, stdio: ['pipe', 'pipe', 'pipe'] });
    this.buffer = '';
    this.stderr = '';
    this.pending = null;
    this.closed = new Promise((resolve) => {
      this.child.on('close', (code) => {
        this.exited = true;
        if (this.pending) {
          const error = new Error(this.stderr || `psql exited ${code}`);
          error.code = this.stderr.match(/ERROR:\s+([A-Z0-9]{5}):/)?.[1];
          this.finish(error);
        }
        resolve();
      });
    });
    this.child.on('error', (error) => this.finish(error));
    this.child.stdin.on('error', (error) => this.finish(error));
    this.child.stderr.on('data', (part) => { this.stderr += part; });
    this.child.stdout.on('data', (part) => {
      this.buffer += part;
      const pending = this.pending;
      if (!pending) return;
      const marker = `${pending.marker}\n`;
      const end = this.buffer.indexOf(marker);
      if (end >= 0) {
        const output = this.buffer.slice(0, end).trim();
        this.buffer = this.buffer.slice(end + marker.length);
        this.finish(null, output);
      }
    });
    cluster.sessions.add(this);
  }
  finish(error, output) {
    if (!this.pending) return;
    const pending = this.pending;
    this.pending = null;
    clearTimeout(pending.timer);
    if (error) pending.reject(error); else pending.resolve(output);
  }
  query(sql) {
    assert(!this.pending && !this.exited, 'Session unavailable');
    return new Promise((resolve, reject) => {
      const marker = `done_${randomUUID().replaceAll('-', '')}`;
      const timer = setTimeout(() => {
        this.finish(new Error('SQL deadline exceeded'));
        this.child.kill('SIGTERM');
      }, 12000);
      this.pending = { marker, timer, resolve, reject };
      this.child.stdin.write(`${sql}\n;\n\\echo ${marker}\n`);
    });
  }
  async close() {
    if (!this.exited) {
      if (this.pending) this.child.kill('SIGTERM');
      else this.child.stdin.end('\\q\n');
    }
    await this.closed;
  }
}

export async function disposableCluster(t, pgBin) {
  assert(pgBin && isAbsolute(pgBin), 'Set PG_BIN to the approved PostgreSQL 17 bin directory');
  let bin = await realpath(pgBin);
  const root = await mkdtemp('/private/tmp/cleanstream-wallet-locking-policy-pg-');
  await chmod(root, 0o700);
  const identity = await lstat(root);
  const socket = join(root, 'socket');
  await mkdir(socket, { mode: 0o700 });
  const data = join(root, 'data');
  const env = {
    PATH: `${bin}:/usr/bin:/bin`, HOME: root, TMPDIR: root, LANG: 'C', LC_ALL: 'C',
    PGCONNECT_TIMEOUT: '5',
  };
  const cluster = { bin, root, socket, env, sessions: new Set() };
  let started = false;
  let startAttempted = false;
  let cleanup;
  let interrupted = false;
  let finishInitialization;
  const initialized = new Promise((resolve) => { finishInitialization = resolve; });
  const signals = new Map();
  const assertOwned = async () => {
    assert(root.startsWith('/private/tmp/cleanstream-wallet-locking-policy-pg-'));
    assert.equal(await realpath(root), root);
    const current = await lstat(root);
    assert(current.isDirectory() && !current.isSymbolicLink());
    assert.equal(current.ino, identity.ino);
    assert.equal(current.dev, identity.dev);
    assert.equal(current.uid, process.getuid());
    assert.equal(current.mode & 0o777, 0o700);
  };
  cluster.close = () => cleanup ??= (async () => {
    for (const [signal, handler] of signals) process.removeListener(signal, handler);
    for (const session of cluster.sessions) await session.close();
    await assertOwned();
    const hasPid = await access(join(data, 'postmaster.pid')).then(() => true, (error) => {
      if (error.code !== 'ENOENT') throw error;
      return false;
    });
    if (started || (startAttempted && hasPid)) {
      try {
        await command(join(bin, 'pg_ctl'), ['-D', data, '-m', 'fast', '-w', '-t', '10', 'stop'], env);
      } catch {
        // Only this freshly initialized cluster can reach the fallback.
        await command(join(bin, 'pg_ctl'), ['-D', data, '-m', 'immediate', '-w', '-t', '10', 'stop'], env);
      }
      started = false;
      t.diagnostic('Owned PostgreSQL cluster stopped');
    }
    await assert.rejects(access(join(data, 'postmaster.pid')), { code: 'ENOENT' });
    await rm(root, { recursive: true });
    t.diagnostic(`Owned disposable directory removed: ${root}`);
  })();
  t.after(cluster.close);
  for (const signal of ['SIGINT', 'SIGTERM']) {
    const handler = () => {
      interrupted = true;
      initialized.then(cluster.close).then(() => process.exit(1), (error) => {
        process.stderr.write(`Disposable cluster cleanup failed: ${error.message}\n`);
        process.exit(1);
      });
    };
    signals.set(signal, handler);
    process.once(signal, handler);
  }
  try {
    const version = await command(join(bin, 'postgres'), ['--version'], env);
    assert.match(version, /PostgreSQL\) 17\./);
    t.diagnostic(`${version}; private Unix socket; listen_addresses empty`);
    const sharedir = await command(join(bin, 'pg_config'), ['--sharedir'], env);
    try {
      await access(join(sharedir, 'postgres.bki'));
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      // Unlinked Homebrew bottles retain compiled share/lib paths. PostgreSQL
      // supports relocation when the original bin suffix is preserved. Copy
      // executables only into our disposable root; never link global paths.
      const bottle = bin.match(/^(.*)\/Cellar\/(postgresql@17)\/([^/]+)\/bin$/);
      assert(bottle, 'Runtime share directory missing; supply a complete local PG_BIN');
      const prefix = dirname(bin);
      const runtime = join(root, 'runtime');
      const relocatedBin = join(runtime, 'Cellar', bottle[2], bottle[3], 'bin');
      await cp(bin, relocatedBin, { recursive: true, dereference: true });
      await mkdir(join(runtime, 'share'), { recursive: true });
      await mkdir(join(runtime, 'lib'), { recursive: true });
      await symlink(join(prefix, 'share', 'postgresql'), join(runtime, 'share', bottle[2]));
      await symlink(join(prefix, 'lib', 'postgresql'), join(runtime, 'lib', bottle[2]));
      bin = relocatedBin;
      cluster.bin = bin;
      env.PATH = `${bin}:/usr/bin:/bin`;
      assert.equal(await command(join(bin, 'pg_config'), ['--sharedir'], env), join(runtime, 'share', bottle[2]));
      assert.equal(await command(join(bin, 'pg_config'), ['--pkglibdir'], env), join(runtime, 'lib', bottle[2]));
      t.diagnostic('Unlinked bottle relocated entirely inside owned disposable directory');
    }
    await command(join(bin, 'initdb'), [
      '-D', data, '--username=policy_fixture', '--auth-local=trust',
      '--auth-host=reject', '--no-locale', '--encoding=UTF8',
    ], env);
    assert(!interrupted, 'Interrupted during cluster initialization');
    await assertOwned();
    startAttempted = true;
    await command(join(bin, 'pg_ctl'), [
      '-D', data, '-l', join(root, 'server.log'), '-w', '-t', '10',
      '-o', `-c listen_addresses='' -c unix_socket_directories='${socket}' -c unix_socket_permissions=0700 -p 55432`,
      'start',
    ], env);
    started = true;
    assert(!interrupted, 'Interrupted during cluster startup');
    await command(join(bin, 'createdb'), [
      '--no-password', '-h', socket, '-p', '55432', '-U', 'policy_fixture', 'loyalty_policy_fixture',
    ], env);
    cluster.connect = async () => {
      const session = new Session(cluster);
      const config = JSON.parse(await session.query(`select json_build_object(
        'db',current_database(),'user',current_user,'data',current_setting('data_directory'),
        'listen',current_setting('listen_addresses'),'address',inet_server_addr(),
        'socket',current_setting('unix_socket_directories'),'pid',pg_backend_pid());`));
      assert.equal(config.db, 'loyalty_policy_fixture');
      assert.equal(config.user, 'policy_fixture');
      assert.equal(config.data, data);
      assert.equal(config.listen, '');
      assert.equal(config.address, null);
      assert.equal(config.socket, socket);
      session.pid = config.pid;
      await session.query("set statement_timeout='10s'; set deadlock_timeout='150ms';");
      return session;
    };
    finishInitialization();
    return cluster;
  } catch (error) {
    finishInitialization();
    await cluster.close();
    throw error;
  }
}

export async function blocked(observer, waiting, holder) {
  const end = Date.now() + 5000;
  while (Date.now() < end) {
    if (await observer.query(`select ${holder.pid}=any(pg_blocking_pids(${waiting.pid}));`) === 't') return;
    await delay(15);
  }
  throw new Error(`Expected backend ${waiting.pid} to wait for ${holder.pid}`);
}
