import asyncio
import aiorcon
from config import settings

async def send_rcon_command(command: str):
    try:
        # O segredo: asyncio.wait_for força um limite de 5 segundos na conexão!
        rcon_client = await asyncio.wait_for(
            aiorcon.RCON.create(
                settings.PZ_RCON_HOST, 
                settings.PZ_RCON_PORT, 
                settings.PZ_RCON_PASSWORD
            ),
            timeout=5.0
        )
        
        response = await asyncio.wait_for(rcon_client(command), timeout=5.0)
        rcon_client.close()
        
        print(f"[RCON SUCCESS] {command} | Resposta: {response}")
        return {"ok": True, "status": "success", "response": response}
        
    except asyncio.TimeoutError:
        print("[RCON ERROR] Timeout - O RCON não atendeu a tempo!")
        return {"ok": False, "status": "rcon_timeout", "message": "RCON demorou muito para responder."}
    except Exception as e:
        print(f"[RCON ERROR] Falha: {e}")
        return {"ok": False, "status": "rcon_error", "message": str(e)}
