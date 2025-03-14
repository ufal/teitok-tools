from phonemizer.backend import EspeakBackend
from phonemizer.punctuation import Punctuation
from phonemizer.separator import Separator
from langcodes import *
import argparse
import lxml.etree as etree
import sys, os, string

parser = argparse.ArgumentParser(description="Provide each word in a TEITOK document with a phonetic transcription")
parser.add_argument("file", help="TEITOK file to transcribe")
parser.add_argument("-l", "--lang", help="language of the file", type=str)
parser.add_argument("--force", help="force when trancription exists", action="store_true")
parser.add_argument("-s", "--sep", help="separator between phones", type=str, default=" ")
parser.add_argument("-a", "--attr", help="attribute to your for transcription", type=str, default="phon")
parser.add_argument("--languages", help="list supported languages", action="store_true")
args = parser.parse_args()

# Get the list of supported languages
supported_languages = EspeakBackend.supported_languages()

if args.languages:
	print ("Supported languages:")
	print (supported_languages)
	exit()
	

xmlf = etree.parse(args.file)
# separate phones by a space and ignoring words boundaries
separator = Separator(phone=args.sep, word=None)



esplan = {}
for langkey in supported_languages:
	esplan[langkey] = langkey
	esplan[supported_languages[langkey]] = langkey
	try:
		langit = Language.find(supported_languages[langkey])
	except LookupError as e:
		continue
	esplan[str(langit)] = langkey
	esplan[langit.display_name()] = langkey
	esplan[langit.to_alpha3()] = langkey
	
langnode = xmlf.find("//langUsage/language")
langcode = args.lang
if langnode is not None and not langcode: 
	langcode = str(langnode.text)
	args.lang = langcode
if not langcode:
	print ("Please specify a language (if not specified in XML)")
	exit()

langid = esplan[langcode]
try:
	langit = Language.find(langcode)
except LookupError as e:
	print ("No found a language for: ", langcode)
	exit()
	
if not langid:
	langit = Language.find(langcode)
	langcode = langit.display_name()
	langid = esplan[langcode]

if not langid:
	print ("No support for: ", args.lang)
	exit()
	
print ("Language: ", str(langid), langit.display_name())

# initialize the espeak backend for English
try:
	backend = EspeakBackend(str(langid))
except RuntimeError as e:
	print (e)
	exit()

for tok in xmlf.iter('tok'):
	word = tok.text
	if not word: 
		continue
	phon = backend.phonemize([word], separator=separator, strip=True)[0].strip()
	if phon and ( args.force or not args.attr in tok.attrib ):
		tok.attrib[args.attr] = phon
		
xmlf.write(args.file,encoding="UTF-8")	
print('Output written back to ' + args.file)
	
