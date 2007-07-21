#!/usr/bin/env python

import random, time
from select import select

from gearman.compat import *
from gearman.connection import GearmanConnection
from gearman.task import Task, Taskset

class GearmanBaseClient(object):
    class ServerUnavailable(Exception): pass
    class CommandError(Exception): pass
    class InvalidResponse(Exception): pass

    def __init__(self, job_servers, prefix=None, pre_connect=False):
        """
        job_servers = ['host:post', 'host', ...]
        """
        self.prefix = prefix and "%s\t" % prefix or ""
        self.set_job_servers(job_servers, pre_connect)

    def set_job_servers(self, servers, pre_connect = False):
        # TODO: don't shut down dups and shut down old ones gracefully
        self.connections = []
        for serv in servers:
            connection = GearmanConnection(serv)
            if pre_connect:
                try:
                    connection.connect()
                except connection.ConnectionError:
                    pass # TODO: connection IS marked as dead but perhaps we don't want it at all
            self.connections.append( connection )

class GearmanClient(GearmanBaseClient):
    class TaskFailed(Exception): pass

    def do_task(self, task):
        """Return the result of the task or raise a TaskFailed exception on failure."""
        def _on_fail():
            raise self.TaskFailed("Task failed")
        task.on_fail.append(_on_fail)
        ts = Taskset( [task] )
        self.do_taskset( ts )
        return task.result

    def dispatch_background_task(self, func, arg, uniq=None, high_priority=False):
        """Submit a background task and return its handle."""
        task = Task(func, arg, uniq, background=True, high_priority=True)
        ts = Taskset( [task] )
        self.do_taskset( ts )
        return task.handle

    def get_server_from_hash(self, hsh):
        """Return a live connection for the given hash"""
        # TODO: instead of cycling through, should we shuffle the list if the first connection fails or is dead?
        first_idx = hsh % len(self.connections)
        for idx in range(first_idx, len(self.connections)) + range(0, first_idx):
            conn = self.connections[idx]
            if conn.is_dead:
                continue

            try:
                conn.connect() # Make sure the connection is up (noop if already connected)
            except conn.ConnectionError:
                pass
            else:
                return conn

        raise self.ServerUnavailable("Unable to Locate Server")

    def _submit_task(self, task):
        server = self.get_server_from_hash(hash(task))
        server.send_command(
            (task.background and "submit_job_bg") or
                (task.high_priority and "submit_job_high") or
                "submit_job",
            dict(func=self.prefix + task.func, arg=task.arg, uniq=task.uniq))
        server.waiting_for_handles.insert(0,task)
        return server

    def _command_handler(self, taskset, conn, cmd, args):
        # DEBUG and _D( "RECEIVED COMMAND:", cmd, args )

        handle = ('handle' in args) and ("%s//%s" % (conn.hostspec, args['handle'])) or None

        if cmd != 'job_created' and handle:
            task = taskset.get( taskset.handles.get(handle, None), None)
            if not task or task.is_finished:
                raise self.InvalidResponse()

        if cmd == 'work_complete':
            task.complete(args['result'])
        elif cmd == 'work_fail':
            if task.retries_done < task.retry_count:
                _D("RETRYING", task)
                task.retries_done += 1
                task.retrying()
                task.handle = None
                taskset.connections.add(self._submit_task(task))
            else:
                task.fail()
        elif cmd == 'work_status':
            task.status(int(args['numerator']), int(args['denominator']))
        elif cmd == 'job_created':
            task = conn.waiting_for_handles.pop()
            task.handle = handle
            taskset.handles[handle] = hash( task )
            if task.background:
                task.is_finished = True
            # _D( "Assigned H[%r] from S[%s] to T[%s]" % (handle, '%s:%s' % conn.addr, hash(task) ))
        elif cmd == 'error':
            raise self.CommandError(str(args)) # TODO make better
        else:
            raise Exception("Unexpected command: %s" % cmd)

        # _D( "HANDLES:", taskset.handles )

    def do_taskset(self, taskset, timeout=None):
        """Execute a Taskset and return True iff all tasks finished before timeout."""

        # set of connections to which jobs were submitted
        taskset.connections = set(self._submit_task(task) for task in taskset.itervalues())

        start_time = time.time()
        end_time = timeout and start_time + timeout or 0
        while not taskset.cancelled and not all(t.is_finished for t in taskset.itervalues()):
            timeleft = timeout and end_time - time.time() or 0.5
            if timeleft <= 0:
                taskset.cancel()
                break

            rx_socks = [c for c in taskset.connections if c.readable()]
            tx_socks = [c for c in taskset.connections if c.writable()]
            rd, wr, ex = select(rx_socks, tx_socks, taskset.connections, timeleft)

            for conn in ex:
                pass # TODO

            for conn in rd:
                for cmd in conn.recv():
                    self._command_handler(taskset, conn, *cmd)

            for conn in wr:
                conn.send()

        return all(t.is_finished for t in taskset.itervalues())
