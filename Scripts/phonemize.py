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
args = parser.parse_args()


xmlf = etree.parse(args.file)
# separate phones by a space and ignoring words boundaries
separator = Separator(phone=args.sep, word=None)

langnode = xmlf.find("//langUsage/language")
langname = args.lang
if langnode is not None and not langname: 
	langname = langnode.text
if not langname:
	print ("Please specify a language (if not specified in XML)")
	exit()
langcode = Language.find(langname) # .to_alpha3()

print ("Language: ", str(langcode), langcode.display_name())

# initialize the espeak backend for English
backend = EspeakBackend(str(langcode))

for tok in xmlf.iter('tok'):
	word = tok.text
	if not word: 
		continue
	phon = backend.phonemize([word], separator=separator, strip=True)[0].strip()
	if phon and ( args.force or not args.attr in tok.attrib ):
		tok.attrib[args.attr] = phon
		
xmlf.write(args.file,encoding="UTF-8")	
print('Output written back to ' + args.file)
	
