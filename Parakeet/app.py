import io, tempfile, torchaudio, soundfile as sf, os
import nemo.collections.asr as nemo_asr
from fastapi import FastAPI, UploadFile, File, HTTPException, Body
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import logging
import torch
import boto3
from botocore.exceptions import ClientError
from moviepy.editor import VideoFileClip
from typing import Optional, Dict, Any
from dotenv import load_dotenv

# Configure logging
logging.basicConfig(level=logging.INFO, 
                    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Load environment variables from .env file if present
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), '.env'))

# S3/MinIO configuration from environment variables
S3_ENDPOINT = os.getenv('S3_ENDPOINT', 'http://minio:9000')
S3_ACCESS_KEY = os.getenv('S3_ACCESS_KEY')
S3_SECRET_KEY = os.getenv('S3_SECRET_KEY')
S3_REGION = os.getenv('S3_REGION', '')

# Log S3 configuration (without exposing full secrets)
access_key_hint = S3_ACCESS_KEY[:4] + '...' if S3_ACCESS_KEY else 'Not set'
secret_key_hint = S3_SECRET_KEY[:4] + '...' if S3_SECRET_KEY else 'Not set'
logger.info(f"S3 Configuration: ENDPOINT={S3_ENDPOINT}, ACCESS_KEY={access_key_hint}, REGION={S3_REGION}")

# Create a Pydantic model for S3 path input
class S3PathInput(BaseModel):
    bucket: str
    key: str
    region: Optional[str] = None
    credentials: Optional[Dict[str, Any]] = None  # Optional AWS credentials
    endpoint_url: Optional[str] = None  # Allow overriding the S3 endpoint URL

# Helper function to convert audio files to compatible format
def convert_to_compatible_audio(input_path, output_path=None):
    """
    Convert various audio/video formats to WAV format suitable for transcription
    
    Args:
        input_path: Path to input file
        output_path: Path to output WAV file (optional, will create temp file if not provided)
    
    Returns:
        Path to the converted WAV file
    """
    file_extension = os.path.splitext(input_path)[1].lower()
    
    # If output path is not provided, create a temporary file
    if not output_path:
        output_file = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        output_path = output_file.name
        output_file.close()
    
    # Process based on file type
    try:
        if file_extension in ['.mp4', '.avi', '.mkv', '.mov', '.webm']:
            # Video file - extract audio
            logger.info(f"Converting video {file_extension} to wav")
            video = VideoFileClip(input_path)
            # Extract audio to a temporary file
            temp_audio_path = output_path + ".temp.wav"
            video.audio.write_audiofile(temp_audio_path, codec='pcm_s16le', verbose=False, logger=None)
            video.close()
            
            # Now load the audio with torchaudio and convert to mono if needed
            data, sample_rate = torchaudio.load(temp_audio_path)
            if data.shape[0] > 1:
                logger.info(f"Converting {data.shape[0]}-channel video audio to mono")
                data = torch.mean(data, dim=0, keepdim=True)
            torchaudio.save(output_path, data, sample_rate)
            
            # Clean up temp file
            os.remove(temp_audio_path)
        elif file_extension in ['.mp3', '.ogg', '.aac', '.m4a', '.flac']:
            # Audio file - convert format if needed
            logger.info(f"Converting audio {file_extension} to wav")
            data, sample_rate = torchaudio.load(input_path)
            # Convert to mono if it's stereo
            if data.shape[0] > 1:
                logger.info(f"Converting {data.shape[0]}-channel audio to mono")
                data = torch.mean(data, dim=0, keepdim=True)
            torchaudio.save(output_path, data, sample_rate)
        elif file_extension == '.wav':
            # Already WAV - just copy if output path is different and ensure mono
            data, sample_rate = torchaudio.load(input_path)
            # Convert to mono if it's stereo
            if data.shape[0] > 1:
                logger.info(f"Converting {data.shape[0]}-channel audio to mono")
                data = torch.mean(data, dim=0, keepdim=True)
            torchaudio.save(output_path, data, sample_rate)
        else:
            raise ValueError(f"Unsupported file format: {file_extension}")
        
        return output_path
    
    except Exception as e:
        logger.error(f"Conversion error: {e}")
        # Clean up temp file if we created one
        if not output_path and os.path.exists(output_path):
            os.unlink(output_path)
        raise

# Determine device (GPU if available, otherwise CPU)
DEVICE = os.getenv("TRANSCRIBE_DEVICE", "cuda" if torch.cuda.is_available() else "cpu")
logger.info(f"Using device: {DEVICE}")

# Add memory management settings
USE_FP16 = os.getenv("USE_FP16", "true").lower() in ["true", "1", "yes"]
MAX_BATCH_SIZE = int(os.getenv("MAX_BATCH_SIZE", "1"))
OPTIMIZE_MEMORY = os.getenv("OPTIMIZE_MEMORY", "true").lower() in ["true", "1", "yes"]

logger.info(f"Memory settings: FP16={USE_FP16}, MAX_BATCH={MAX_BATCH_SIZE}, OPTIMIZE_MEMORY={OPTIMIZE_MEMORY}")

# Load the model with error handling
try:
    # Free up CUDA memory before loading model
    if DEVICE == "cuda":
        torch.cuda.empty_cache()
        logger.info(f"CUDA memory before model load: {torch.cuda.memory_allocated(0) / 1024 / 1024:.2f}MB allocated")
    
    # Use appropriate precision based on settings
    dtype = torch.float16 if USE_FP16 and DEVICE == "cuda" else None
    
    model = nemo_asr.models.ASRModel.from_pretrained(
        model_name="nvidia/parakeet-tdt-0.6b-v2",
        map_location=DEVICE
    )
    
    # Apply additional memory optimizations after loading
    if DEVICE == "cuda":
        if OPTIMIZE_MEMORY:
            # Attempt to convert to half precision to save memory if requested
            if USE_FP16:
                logger.info("Converting model to half precision (FP16)")
                model = model.half()
            
            # Free unused memory
            torch.cuda.empty_cache()
        
        logger.info(f"CUDA memory after model load: {torch.cuda.memory_allocated(0) / 1024 / 1024:.2f}MB allocated")
        
    logger.info("Parakeet model loaded successfully")
except Exception as e:
    logger.error(f"Failed to load model: {e}")
    raise

# Initialize FastAPI app
app = FastAPI(
    title="Parakeet-v2 ASR",
    description="Speech-to-text API using NVIDIA's Parakeet-TDT model",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allows all origins
    allow_credentials=True,
    allow_methods=["*"],  # Allows all methods
    allow_headers=["*"],  # Allows all headers
)

@app.get("/")
async def root():
    """Health check endpoint"""
    return {"status": "ok", "model": "parakeet-tdt-0.6b-v2", "device": DEVICE}

@app.get("/s3-status")
async def s3_status(endpoint_url: Optional[str] = None):
    """
    Check S3/MinIO connection status
    
    - **endpoint_url**: Optional override for the S3/MinIO endpoint URL
    
    Returns the connection status and available buckets
    """
    try:
        # Set up S3 client kwargs
        s3_kwargs = {}
        
        # Set endpoint_url from query parameter or environment variable
        endpoint_url = endpoint_url or S3_ENDPOINT
        if endpoint_url:
            s3_kwargs['endpoint_url'] = endpoint_url
            s3_kwargs['config'] = boto3.session.Config(signature_version='s3v4', s3={'addressing_style': 'path'})
        
        # Set region from environment variable
        if S3_REGION:
            s3_kwargs['region_name'] = S3_REGION
        
        # Set credentials from environment variables
        if S3_ACCESS_KEY and S3_SECRET_KEY:
            logger.info(f"Using S3 credentials with access key: {access_key_hint}...")
            s3_kwargs['aws_access_key_id'] = S3_ACCESS_KEY
            s3_kwargs['aws_secret_access_key'] = S3_SECRET_KEY
        else:
            logger.warning("No S3 credentials found in environment variables!")
        
        # Create S3 client with all configured parameters
        logger.info(f"Creating S3 client with kwargs: {s3_kwargs}")
        s3_client = boto3.client('s3', **s3_kwargs)
        
        # List buckets to test connection
        response = s3_client.list_buckets()
        
        # Get bucket names
        buckets = [bucket['Name'] for bucket in response.get('Buckets', [])]
        
        return {
            "status": "connected",
            "endpoint": endpoint_url or "default AWS",
            "buckets": buckets,
            "bucket_count": len(buckets)
        }
    except Exception as e:
        logger.error(f"S3 connection error: {e}")
        return {
            "status": "error",
            "endpoint": endpoint_url or "default AWS",
            "error": str(e),
            "help": "Check your S3_ENDPOINT, S3_ACCESS_KEY, and S3_SECRET_KEY environment variables"
        }

@app.post("/transcribe")
async def transcribe(file: UploadFile = File(...)):
    """
    Transcribe speech audio file to text
    
    - **file**: Audio file in a format supported by soundfile (WAV, FLAC, etc.)
    
    Returns the transcribed text
    """
    if not file.filename:
        raise HTTPException(status_code=400, detail="No file provided")
    
    try:
        # Extract file extension for conversion decision
        file_extension = os.path.splitext(file.filename)[1].lower() if file.filename else ".wav"
        
        # Read uploaded file
        file_bytes = await file.read()
        
        # Log file details
        logger.info(f"Processing file: {file.filename}, size: {len(file_bytes)} bytes")
        
        # Create temporary files for processing
        with tempfile.NamedTemporaryFile(suffix=file_extension) as input_tmp, \
             tempfile.NamedTemporaryFile(suffix=".wav") as output_tmp:
            
            # Write uploaded content to temp file
            input_tmp.write(file_bytes)
            input_tmp.flush()
            
            # Convert if needed
            processed_audio = convert_to_compatible_audio(input_tmp.name, output_tmp.name)
            
            # Transcribe audio with memory management
            try:
                # Free up memory before transcription
                if DEVICE == "cuda":
                    torch.cuda.empty_cache()
                    logger.info(f"Pre-transcribe CUDA memory: {torch.cuda.memory_allocated(0) / 1024 / 1024:.2f}MB allocated")
                
                with torch.cuda.amp.autocast(enabled=USE_FP16):
                    text = model.transcribe([processed_audio], batch_size=MAX_BATCH_SIZE)[0].text
                
                # Free up memory after transcription
                if DEVICE == "cuda":
                    torch.cuda.empty_cache()
                    
                logger.info(f"Transcription successful: {len(text)} chars")
                
                return {"text": text}
            except RuntimeError as e:
                if "CUDA out of memory" in str(e):
                    logger.error(f"CUDA OOM error: {e}")
                    # Try with CPU fallback as last resort
                    logger.info("Attempting CPU fallback for transcription")
                    # Move model to CPU temporarily
                    device_backup = model.device
                    model.to("cpu")
                    text = model.transcribe([processed_audio], batch_size=1)[0].text
                    # Move back to original device
                    model.to(device_backup)
                    logger.info(f"CPU fallback transcription successful: {len(text)} chars")
                    return {"text": text}
                else:
                    raise
    except Exception as e:
        logger.error(f"Transcription error: {e}")
        raise HTTPException(status_code=500, detail=f"Error processing audio: {str(e)}")

@app.post("/transcribe-s3")
async def transcribe_s3(s3_input: S3PathInput):
    """
    Transcribe speech audio file from an S3 path
    
    - **bucket**: S3 bucket name
    - **key**: S3 object key (path to the file)
    - **region**: Optional AWS region
    - **credentials**: Optional AWS credentials dict with access_key, secret_key, session_token
    - **endpoint_url**: Optional S3 endpoint URL (for MinIO or other S3-compatible services)
    
    Returns the transcribed text
    """
    try:
        # Set up S3 client kwargs
        s3_kwargs = {}
        
        # Set endpoint_url from input parameter or environment variable
        endpoint_url = s3_input.endpoint_url or S3_ENDPOINT
        if endpoint_url:
            s3_kwargs['endpoint_url'] = endpoint_url
            # For MinIO and other S3-compatible services, path-style addressing is often required
            s3_kwargs['config'] = boto3.session.Config(signature_version='s3v4', s3={'addressing_style': 'path'})
        
        # Set region from input parameter or environment variable
        region = s3_input.region or S3_REGION
        if region:
            s3_kwargs['region_name'] = region
        
        # Set credentials with priority: 1) provided in request, 2) from environment variables
        if s3_input.credentials:
            s3_kwargs['aws_access_key_id'] = s3_input.credentials.get('access_key')
            s3_kwargs['aws_secret_access_key'] = s3_input.credentials.get('secret_key')
            if 'session_token' in s3_input.credentials:
                s3_kwargs['aws_session_token'] = s3_input.credentials.get('session_token')
        elif S3_ACCESS_KEY and S3_SECRET_KEY:
            logger.info(f"Using environment credentials - Access key: {access_key_hint}...")
            s3_kwargs['aws_access_key_id'] = S3_ACCESS_KEY
            s3_kwargs['aws_secret_access_key'] = S3_SECRET_KEY
        else:
            logger.warning("No S3 credentials found! Trying to use instance profile or default credentials...")
        
        # Create S3 client with all configured parameters
        logger.info(f"Creating S3 client with kwargs: {s3_kwargs}")
        s3_client = boto3.client('s3', **s3_kwargs)
        
        logger.info(f"Using S3 endpoint: {endpoint_url or 'default AWS'}")
        
        # Log S3 file details
        logger.info(f"Processing S3 file: s3://{s3_input.bucket}/{s3_input.key}")
        
        # Create temporary file to store the downloaded content
        file_extension = os.path.splitext(s3_input.key)[1].lower()
        
        # Determine if we need to convert (e.g., mp4 to wav)
        needs_conversion = file_extension not in ['.wav', '.flac', '.mp3', '.ogg']
        
        with tempfile.NamedTemporaryFile(suffix=file_extension) as download_tmp:
            # Download the file from S3
            try:
                s3_client.download_fileobj(s3_input.bucket, s3_input.key, download_tmp)
                download_tmp.flush()
                logger.info(f"Downloaded file from S3 successfully")
            except ClientError as e:
                logger.error(f"S3 download error: {e}")
                raise HTTPException(status_code=404, detail=f"Error downloading from S3: {str(e)}")
            
            # Process the file - convert if needed
            try:
                with tempfile.NamedTemporaryFile(suffix=".wav") as audio_tmp:
                    # Convert to compatible audio format (will handle both direct and conversion cases)
                    processed_audio = convert_to_compatible_audio(download_tmp.name, audio_tmp.name)
                    
                    # Transcribe the audio with memory management
                    try:
                        # Free up memory before transcription
                        if DEVICE == "cuda":
                            torch.cuda.empty_cache()
                            logger.info(f"Pre-transcribe CUDA memory: {torch.cuda.memory_allocated(0) / 1024 / 1024:.2f}MB allocated")
                        
                        with torch.cuda.amp.autocast(enabled=USE_FP16):
                            text = model.transcribe([processed_audio], batch_size=MAX_BATCH_SIZE)[0].text
                        
                        # Free up memory after transcription
                        if DEVICE == "cuda":
                            torch.cuda.empty_cache()
                    except RuntimeError as e:
                        if "CUDA out of memory" in str(e):
                            logger.error(f"CUDA OOM error: {e}")
                            # Try with CPU fallback as last resort
                            logger.info("Attempting CPU fallback for transcription")
                            # Move model to CPU temporarily
                            device_backup = model.device
                            model.to("cpu")
                            text = model.transcribe([processed_audio], batch_size=1)[0].text
                            # Move back to original device
                            model.to(device_backup)
                            logger.info(f"CPU fallback transcription successful")
                        else:
                            raise
            except ValueError as e:
                logger.error(f"Format error: {e}")
                raise HTTPException(status_code=400, detail=f"Unsupported file format: {str(e)}")
            except Exception as e:
                logger.error(f"Processing error: {e}")
                raise HTTPException(status_code=500, detail=f"Error processing media: {str(e)}")
            
            logger.info(f"Transcription successful: {len(text)} chars")
            return {"text": text}
            
    except Exception as e:
        logger.error(f"S3 transcription error: {e}")
        raise HTTPException(status_code=500, detail=f"Error processing S3 audio: {str(e)}")
