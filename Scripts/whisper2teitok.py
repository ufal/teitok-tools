import whisper_timestamped as whisper
import lxml.etree as etree
import sys, os, string
import argparse

parser = argparse.ArgumentParser(description="Split XML into plain text and stand-off XML mark-up")
parser.add_argument("infile", help="input audio file name (WAV or MP3)")
parser.add_argument("-o", "--outfolder", help="folder to place the XML file", default="xmlfiles")
parser.add_argument("--confs", help="keep confidence scores", action="store_true")
parser.add_argument("-l", "--language", help="language of the audio", type=str)
args = parser.parse_args()

audiofile = args.infile
withconf = args.confs

audio = whisper.load_audio(audiofile)
audioext = os.path.splitext(os.path.basename(audiofile))[1]
audiobase = os.path.basename(audiofile)

model = whisper.load_model("medium", device="cpu")

result = whisper.transcribe(model, audio, language=args.language)

xmlstring = "<TEI/>"	
xmlf = etree.ElementTree(etree.fromstring(xmlstring))
ttheader = etree.Element("teiHeader")
xmlf.getroot().append(ttheader)
recst = etree.Element("recordingStmt")
ttheader.append(recst)
rec = etree.Element("recording")
recst.append(rec)
rec.set("type", "audio")
media = etree.Element("media")
rec.append(media)
media.set("mimeType", "audio/"+audioext[1:])
media.set("url", "Audio/"+audiobase)
tttext = etree.Element("text")
xmlf.getroot().append(tttext)
if "language" in result.keys():
	tttext.set("lang", result['language'])

uttcnt = 0
tokcnt = 0

for seg in result['segments']:
	utt = etree.Element("u")
	tttext.append(utt)
	utt.set("text", str(seg['text']))
	utt.set("start", str(seg['start']))
	utt.set("end", str(seg['end']))
	uttcnt = uttcnt + 1
	utt.set("id", "u-"+str(uttcnt))
	if withconf:
		utt.set("conf", str(seg['conf']))
	for word in seg['words']:
		tok = etree.Element("tok")
		utt.append(tok)
		tok.text = word['text']
		tok.set("start", str(word['start']))
		tok.set("end", str(word['end']))
		tokcnt = tokcnt + 1
		tok.set("id", "w-"+str(tokcnt))
		if withconf:
			tok.set("conf", str(word['conf']))
		tok.tail = " "
		# Split off punctuation marks
		last = True
		while tok.text[-1] in string.punctuation:
			old = tok.text
			punct = etree.Element("tok")
			punct.text = old[-1]
			tokcnt = tokcnt + 1
			punct.set("id", "w-"+str(tokcnt))
			index = list(utt).index(tok)
			utt.insert(index+1, punct)
			tok.text = old[0:-1]
			if last:
				punct.tail = " "
				tok.tail = ""
			last = False
	utt.tail = "\n"

xmlfile = args.outfolder + '/' + os.path.splitext(os.path.basename(audiofile))[0] + ".xml"
print("output written to " + xmlfile)
xmlf.write(xmlfile,encoding="UTF-8")	
