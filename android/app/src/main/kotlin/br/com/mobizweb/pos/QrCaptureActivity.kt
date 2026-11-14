package br.com.mobizweb.pos

import com.journeyapps.barcodescanner.CaptureActivity

/**
 * Tela do leitor de QR ("Ler QR da comanda"). É a `CaptureActivity` do
 * ZXing sem mudança de comportamento: existe só para ser declarada no
 * manifest em RETRATO (a da biblioteca abre em paisagem).
 */
class QrCaptureActivity : CaptureActivity()
