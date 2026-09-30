#!/usr/bin/env python3
"""Loopback SOCKS5: desktop IPv4 VPN when routed, otherwise router SOCKS.
Never fall back to physical-network direct access. No destination logging.
"""
import asyncio
import ipaddress
import socket
import struct

async def interface(address):
    proc = await asyncio.create_subprocess_exec('/sbin/route', '-n', 'get', address,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
    out, _ = await proc.communicate()
    if proc.returncode:
        raise OSError('route lookup failed')
    for line in out.decode().splitlines():
        if line.strip().startswith('interface:'):
            return line.split(':', 1)[1].strip()
    raise OSError('route interface missing')

async def mode():
    a, b = await asyncio.gather(interface('1.1.1.1'), interface('8.8.8.8'))
    return a if a == b and a.startswith(('utun', 'tun', 'ppp')) else 'router'

async def address(reader):
    atyp = (await reader.readexactly(1))[0]
    if atyp == 1:
        raw = await reader.readexactly(4)
        host = socket.inet_ntop(socket.AF_INET, raw)
        encoded = bytes([atyp]) + raw
    elif atyp == 3:
        size = await reader.readexactly(1)
        raw = await reader.readexactly(size[0])
        host = raw.decode('ascii')
        encoded = bytes([atyp]) + size + raw
    elif atyp == 4:
        raw = await reader.readexactly(16)
        host = socket.inet_ntop(socket.AF_INET6, raw)
        encoded = bytes([atyp]) + raw
    else:
        raise OSError('unsupported address')
    port = await reader.readexactly(2)
    return host, struct.unpack('!H', port)[0], encoded + port

async def pump(reader, writer):
    while data := await reader.read(65536):
        writer.write(data)
        await writer.drain()

active = set()

async def handle(reader, writer):
    upstream = None
    try:
        ver, count = await reader.readexactly(2)
        methods = await reader.readexactly(count)
        if ver != 5 or 0 not in methods:
            writer.write(b'\x05\xff')
            return
        writer.write(b'\x05\x00')
        await writer.drain()
        ver, command, reserved = await reader.readexactly(3)
        if (ver, command, reserved) != (5, 1, 0):
            raise OSError('CONNECT only')
        host, port, encoded = await address(reader)
        selected = await mode()
        if selected == 'router':
            remote, upstream = await asyncio.open_connection('127.0.0.1', 10819)
            upstream.write(b'\x05\x01\x00')
            await upstream.drain()
            if await remote.readexactly(2) != b'\x05\x00':
                raise OSError('router SOCKS negotiation failed')
            upstream.write(b'\x05\x01\x00' + encoded)
            await upstream.drain()
            reply = await remote.readexactly(3)
            _, _, bound = await address(remote)
            if reply[:2] != b'\x05\x00':
                raise OSError('router SOCKS connection failed')
        else:
            # IPv4 only: IPv6 must never silently take a different physical route.
            infos = await asyncio.get_running_loop().getaddrinfo(host, port,
                family=socket.AF_INET, type=socket.SOCK_STREAM)
            target = infos[0][4][0]
            if ipaddress.ip_address(target).is_loopback or await interface(target) != selected:
                raise OSError('target is outside desktop VPN')
            remote, upstream = await asyncio.open_connection(target, port, family=socket.AF_INET)
            if await mode() != selected:
                raise OSError('VPN changed during connection')
        writer.write(b'\x05\x00\x00\x01' + b'\x00' * 6)
        await writer.drain()
        active.add(writer)
        active.add(upstream)
        tasks = [asyncio.create_task(pump(reader, upstream)), asyncio.create_task(pump(remote, writer))]
        try:
            await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        finally:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
    except (OSError, asyncio.IncompleteReadError, UnicodeError):
        writer.write(b'\x05\x01\x00\x01' + b'\x00' * 6)
    finally:
        for stream in (writer, upstream):
            if stream:
                active.discard(stream)
                stream.close()

async def watchdog():
    previous = None
    while True:
        try:
            current = await mode()
        except OSError:
            current = 'unknown'
        if current != previous:
            for stream in tuple(active):
                stream.close()
            print('mode=' + current, flush=True)
            previous = current
        await asyncio.sleep(1)

async def main():
    server = await asyncio.start_server(handle, '127.0.0.1', 10809)
    async with server:
        await asyncio.gather(server.serve_forever(), watchdog())

if __name__ == '__main__':
    asyncio.run(main())
