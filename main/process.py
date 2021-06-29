import os
import nv
import dlib
from correlation_tracker import CorrelationTracker as CT
from trackable_object import TrackableObject
from imutils.video import VideoStream
from imutils.video import FPS
import numpy as np
import face_recognition
import imutils
import time
import dlib
import cv2
import sys


def ensure_dir(directory):
	if not os.path.exists(directory):
        	os.makedirs(directory)

def writeOutImg(name, frame):
	try:
		name, confidence = (name.split('_')[0]), (name.split('_')[1])
	except:
		name, confidence = (name, "N/A")
	path = (nv.DATA_DIR + nv.sep + "objects" + nv.sep + name)
	ensure_dir(path)
	count = (len(os.listdir(path)) + 1)
	fname = (path + nv.sep + str(count) + ".jpg")
	cv2.imwrite(fname, frame)

def recognize(camera_id, img):
	name = None
	matches = []
	face_location = None
	if img is not None:
		test_face = face_recognition.face_encodings(img)
		test_location = face_recognition.face_locations(img)
		if len(test_face) == 0:
			name, test_location = (None, None)
		else:
			name = "Unidentified Face"
			result = face_recognition.compare_faces(nv.KNOWN_ENCODINGS, test_face)
			if True in result:
				i = result.index(True)
				name = nv.KNOWN_NAMES[i]
				splitter = '_'
				name = name.split(splitter)[0]
				print ("I see " + name + "...")
		if test_location is not None:
			out = (name, test_location[0])
			#nv.writeIoFile(camera_id, matches)
			return (out)
		else:
			return (None, None)

def face_detect(img):
	gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)# convert to grayscale
	faces = face_cascade.detectMultiScale(gray, 1.1, 4)#detect faces
	hasface = False
	if type(faces) == list:
		if faces.any():
			hasface = True
	elif type(faces) == tuple:
		if faces:
			hasface = True

	if hasface == True:
		faces_ct = len(faces)
		name = ("Detected face (" + str(faces_ct) + ")")
		ts = time.time()#get timestamp to test for stale processes.
		for (x, y, w, h) in faces:
			cv2.rectangle(img, (x, y), (x+w, y+h), (255, 0, 0), 2)#draw rectangle over face on image.
			box = (x, y, (x+w), (y+h))
		return (name, box)
	else:
		return (None, None)

try:
	camera_id = int(sys.argv[1])
except:
	camera_id = int(1)
src = nv.CAMERAS[camera_id] 
CLASSES = nv.OBJECTDETECTOR_CLASSES
net = cv2.dnn.readNetFromCaffe(nv.PROTOTXT, nv.MODEL)
vs = cv2.VideoCapture(src)
W = None
H = None
trackers = {}
trackableObjects = {}
totalFrames = 0
totalDown = 0
totalUp = 0
#src="rtsp://monkey:N0712731l@192.168.2.4:9876/h264_pcm.sdp"
vs = cv2.VideoCapture(src)
output = []
status = "Waiting"
writeout = None
face_cascade = cv2.CascadeClassifier(nv.HAARFILE)
tracker = None
while True:
	ret, frame = vs.read()
	if ret == False:
		continue
	if totalFrames % nv.SKIP_FRAMES == 0:
		#rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
		frame = imutils.resize(frame, width=400)
		(H, W) = frame.shape[:2]
		rects = []
		status = "Detecting"
		if "face_detection" in nv.METHODS:
			name, box = face_detect(frame)
			if name is not None and box is not None:
				out = (name, box)
				output.append(out)
		elif "object_detection" in nv.METHODS:
			blob = cv2.dnn.blobFromImage(frame, 0.007843, (W, H), 127.5)
			net.setInput(blob)
			detections = net.forward()
			output = []
			out = ()
			object_id = 0
			for i in np.arange(0, detections.shape[2]):
				object_id = object_id + 1
				writeout = None
				cars = 0
				confidence = detections[0, 0, i, 2]
				idx = int(detections[0, 0, i, 1])
				name = nv.OBJECTDETECTOR_CLASSES[idx]
				if name in nv.OBJECTDETECTOR_TARGETS and confidence > nv.OBJECTDETECTOR_CONFIDENCE:
					dets = detections[0, 0, i, 3:7] * np.array([W, H, W, H])
					(l, t, r, b) = dets.astype("int")
					box = (l, t, r, b)
					tracker = CT(box, frame)
					rects.append((l, t, r, b))
					#objects = ct.update(rects)
					text = name + "_" + str(confidence)
					trackers[object_id] = (text, tracker)
					out = (text, box)
					if name == "car" and camera_id == 1:
						cars = cars + 1
						if cars > 1:
							writeOutImg(text, frame)
					elif name == "car" and camera_id != 1:
						writeOutImg(text, frame)
					elif name == "person":
						facedata = face_recognition.face_locations(frame)
						if facedata != []:
							for face in facedata:
								out = (name, face)
								recname, recface = recognize(camera_id, frame)
								if recname is not None:
									text = recname
									out = (text, recface)
								else:
									text = "Unrecognized: Unidentified Person"
									out = (text, face)
						output.append(out)
						trackers[object_id] = (text, tracker)
						writeOutImg(text, frame)
		elif "face_recognition" in nv.METHODS:
			name, box = face_detect(frame)
			if name is not None and box is not None:
				tracker = CT(box, frame)
				facedata = face_recognition.face_locations(frame)
				if facedata != []:
					for face in facedata:
						out = (name, face)
						recname, recface = recognize(camera_id, frame)
						if recname is not None:
							text = recname
							out = (text, recface)
						else:
							text = "Unrecognized: Unidentified Person"
							out = (text, face)
			else:
				text = "Detected: Unknown Person"
				if box is not None:
					l, t, r, b = box
					rect = dlib.rectangle(l, t, r, b)
					tracker = CT(text, rect)
					out = (text, box)
				else:
					out = ("All fucked up", None)
			output.append(out)
			if tracker is not (None):
				object_id = len(list(trackers.keys()))
				object_id = object_id + 1
				trackers[object_id] = (text, tracker)
			writeOutImg(text, frame)
			
	else:
		output = []
		status = "Tracking"
		to_del = {}
		string = "dict_keys([])"
		test_str = str(trackers.keys())
		if test_str == string:	
			out = (None, None)
			output.append(out)
		else:
			for object_id in trackers.keys():
				name, tracker = trackers[object_id]
				name = name.split('_')[0]#parse confidence (from detector) out of string
				age, confidence, rect = tracker.predict(frame)#calulcate age of object
				if age > nv.TRACKER_MAX_AGE:# if max age has occured...
					to_del[object_id] = object_id#...flag object for removal
				confidence = (confidence / 10)
				name = (name + "_" + str(confidence))
				#if confidence > nv.OBJECTDETECTOR_CONFIDENCE and age < nv.TRACKER_MAX_AGE:
				out = (name, box)
				output.append(out)
		for object_id in to_del.keys():
			del trackers[object_id]

	totalFrames = totalFrames + 1
	if writeout is not None:
		fname, frame = writeout
		cv2.imwrite()
	if output != []:
		nv.writeIoFile(camera_id, output)


