"""TCP + UDP echo server on 127.0.0.1 for scripts/run-interop.sh."""
import asyncio
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 7000


async def echo(reader, writer):
    try:
        while data := await reader.read(65536):
            writer.write(data)
            await writer.drain()
    except ConnectionError:
        pass
    finally:
        writer.close()


class UdpEcho(asyncio.DatagramProtocol):
    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data, address):
        self.transport.sendto(data, address)


async def main():
    loop = asyncio.get_running_loop()
    await loop.create_datagram_endpoint(UdpEcho, local_addr=("127.0.0.1", PORT))
    server = await asyncio.start_server(echo, "127.0.0.1", PORT)
    async with server:
        await server.serve_forever()


asyncio.run(main())
