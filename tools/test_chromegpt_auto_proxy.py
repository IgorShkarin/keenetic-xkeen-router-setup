import asyncio
import importlib.util
import unittest
from unittest.mock import AsyncMock, patch
from pathlib import Path

spec = importlib.util.spec_from_file_location('proxy', Path(__file__).with_name('chromegpt_auto_proxy.py'))
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)

class Routes(unittest.IsolatedAsyncioTestCase):
    async def test_full_tunnel(self):
        with patch.object(proxy, 'interface', AsyncMock(return_value='utun8')):
            self.assertEqual(await proxy.mode(), 'utun8')

    async def test_physical_route_uses_router(self):
        with patch.object(proxy, 'interface', AsyncMock(return_value='en0')):
            self.assertEqual(await proxy.mode(), 'router')

    async def test_split_routes_use_router(self):
        with patch.object(proxy, 'interface', AsyncMock(side_effect=['utun7', 'en0'])):
            self.assertEqual(await proxy.mode(), 'router')

    async def test_unknown_route_fails_closed(self):
        with patch.object(proxy, 'interface', AsyncMock(side_effect=OSError('unavailable'))):
            with self.assertRaises(OSError):
                await proxy.mode()

    async def test_vpn_destination_bypass_is_rejected(self):
        reader = asyncio.StreamReader()
        reader.feed_data(b'\x05\x01\x00\x05\x01\x00\x01\x01\x01\x01\x01\x01\xbb')
        class Writer:
            data = b''
            def write(self, value): self.data += value
            async def drain(self): pass
            def close(self): pass
        writer = Writer()
        connection = AsyncMock()
        with patch.object(proxy, 'mode', AsyncMock(return_value='utun8')), patch.object(proxy, 'interface', AsyncMock(return_value='en0')), patch.object(asyncio, 'open_connection', connection):
            await proxy.handle(reader, writer)
        connection.assert_not_called()
        self.assertEqual(writer.data[:4], b'\x05\x00\x05\x01')

if __name__ == '__main__':
    unittest.main()
