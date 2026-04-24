import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from PIL import Image, ImageEnhance
import io
import os
import threading
import numpy as np
from moviepy.editor import VideoFileClip
from imageio_ffmpeg import get_ffmpeg_exe
import subprocess

class ShakalizerApp:
    """
    Shakalizer - Desktop application for degrading image and video quality.
    Creates meme-style "shakal" artifacts (JPEG compression, pixelation, low FPS).
    """
    def __init__(self, root):
        self.root = root
        self.root.title("Shakalizer (Шакализатор)")
        self.root.geometry("480x560")
        self.root.resizable(False, False)

        self.input_file = None
        self.original_fps = 30

        self._build_ui()

    def _build_ui(self):
        # --- UI Elements ---
        self.btn_select = ttk.Button(self.root, text="Выбрать файл (Изображение или Видео)", command=self.select_file)
        self.btn_select.pack(pady=10)

        self.lbl_file = ttk.Label(self.root, text="Файл не выбран", foreground="gray")
        self.lbl_file.pack()

        # Settings Frame
        settings_frame = ttk.LabelFrame(self.root, text="Настройки деградации")
        settings_frame.pack(pady=10, padx=20, fill="x")

        # 1. Quality Slider (JPEG artifacts)
        ttk.Label(settings_frame, text="Уровень шакалов (грязь, JPEG):").pack(anchor="w", padx=5)
        self.quality_var = tk.IntVar(value=80)
        q_frame = ttk.Frame(settings_frame)
        q_frame.pack(fill="x", padx=5, pady=2)
        self.q_scale = ttk.Scale(q_frame, from_=0, to=100, variable=self.quality_var, orient="horizontal")
        self.q_scale.pack(side="left", fill="x", expand=True)
        self.q_entry = ttk.Entry(q_frame, textvariable=self.quality_var, width=4)
        self.q_entry.pack(side="right", padx=5)

        # 2. Pixelation Slider
        ttk.Label(settings_frame, text="Размер пикселя (крупность):").pack(anchor="w", padx=5, pady=(10,0))
        self.pixel_var = tk.IntVar(value=5)
        p_frame = ttk.Frame(settings_frame)
        p_frame.pack(fill="x", padx=5, pady=2)
        self.p_scale = ttk.Scale(p_frame, from_=1, to=50, variable=self.pixel_var, orient="horizontal")
        self.p_scale.pack(side="left", fill="x", expand=True)
        self.p_entry = ttk.Entry(p_frame, textvariable=self.pixel_var, width=4)
        self.p_entry.pack(side="right", padx=5)

        # 3. Posterize Time (FPS)
        self.lbl_fps_title = ttk.Label(settings_frame, text="Posterize Time (FPS):")
        self.lbl_fps_title.pack(anchor="w", padx=5, pady=(10,0))
        self.fps_var = tk.IntVar(value=24)
        f_frame = ttk.Frame(settings_frame)
        f_frame.pack(fill="x", padx=5, pady=2)
        self.fps_scale = ttk.Scale(f_frame, from_=1, to=60, variable=self.fps_var, orient="horizontal")
        self.fps_scale.pack(side="left", fill="x", expand=True)
        self.fps_entry = ttk.Entry(f_frame, textvariable=self.fps_var, width=4)
        self.fps_entry.pack(side="right", padx=5)

        # Video Mode Frame
        frame_mode = ttk.LabelFrame(self.root, text="Режим обработки видео")
        frame_mode.pack(pady=10, padx=20, fill="x")

        self.mode_var = tk.StringVar(value="fast")
        ttk.Radiobutton(frame_mode, text="Быстрый (FFmpeg) - потоковое сжатие", variable=self.mode_var, value="fast").pack(anchor="w", padx=10)
        ttk.Radiobutton(frame_mode, text="Точный (PIL) - покадровый JPEG-ад", variable=self.mode_var, value="accurate").pack(anchor="w", padx=10)

        # Start Button
        self.btn_start = ttk.Button(self.root, text="УШАТАТЬ В ХЛАМ", command=self.start_processing, state="disabled")
        self.btn_start.pack(pady=10)

        self.lbl_status = ttk.Label(self.root, text="Готов", font=("Arial", 9, "bold"))
        self.lbl_status.pack()

    def select_file(self):
        filetypes = (
            ("Медиа файлы", "*.png *.jpg *.jpeg *.mp4 *.avi *.mov *.mkv"), 
            ("Изображения", "*.png *.jpg *.jpeg"),
            ("Видео", "*.mp4 *.avi *.mov *.mkv"),
            ("Все файлы", "*.*")
        )
        filepath = filedialog.askopenfilename(title="Выбери жертву", filetypes=filetypes)
        
        if filepath:
            self.input_file = filepath
            ext = filepath.split('.')[-1].lower()
            
            if ext in['mp4', 'avi', 'mov', 'mkv']:
                try:
                    clip = VideoFileClip(filepath)
                    self.original_fps = int(clip.fps)
                    clip.close()
                    self.fps_scale.config(to=self.original_fps)
                    if self.fps_var.get() > self.original_fps:
                        self.fps_var.set(self.original_fps)
                    self.lbl_fps_title.config(text=f"Posterize Time (FPS)[Макс: {self.original_fps}]:")
                except Exception as e:
                    print(f"Warning: Could not read FPS. {e}")
                    self.original_fps = 60
            
            self.lbl_file.config(text=os.path.basename(filepath), foreground="black")
            self.btn_start.config(state="normal")

    def start_processing(self):
        if not self.input_file:
            return
            
        self.btn_start.config(state="disabled")
        self.lbl_status.config(text="В процессе обработки...", foreground="blue")
        # Run processing in a separate thread to prevent UI freezing
        threading.Thread(target=self.process_file, daemon=True).start()

    def _shakalize_pil_image(self, img, quality, pixel_size):
        """Applies degrading effects to a PIL Image object."""
        if img.mode != 'RGB':
            img = img.convert('RGB')
        
        w, h = img.size
        small_w = max(1, w // pixel_size)
        small_h = max(1, h // pixel_size)
        
        # Pixelate
        img = img.resize((small_w, small_h), Image.Resampling.BOX)
        
        # Degrade quality
        if quality > 0:
            enhancer = ImageEnhance.Contrast(img)
            img = enhancer.enhance(1.0 + (quality / 100.0))
            enhancer = ImageEnhance.Color(img)
            img = enhancer.enhance(1.0 + (quality / 200.0))
            
            jpeg_q = max(1, int(60 - quality * 0.58))
            passes = int(1 + quality / 20)
            
            for _ in range(passes):
                buf = io.BytesIO()
                img.save(buf, format="JPEG", quality=jpeg_q)
                buf.seek(0)
                img = Image.open(buf)

        return img.resize((w, h), Image.Resampling.NEAREST)

    def process_file(self):
        q = self.quality_var.get()
        p = self.pixel_var.get()
        target_fps = self.fps_var.get()
        ext = self.input_file.split('.')[-1].lower()
        base_path = self.input_file.rsplit('.', 1)[0]
        
        try:
            if ext in['png', 'jpg', 'jpeg']:
                output_file = f"{base_path}_shakal.{ext}"
                img = Image.open(self.input_file)
                self._shakalize_pil_image(img, q, p).save(output_file)
            else:
                # Force .mp4 output for videos to avoid codec/container issues
                output_file = f"{base_path}_shakal.mp4"
                if self.mode_var.get() == "accurate":
                    self.process_video_accurate(self.input_file, output_file, q, p, target_fps)
                else:
                    self.process_video_fast(self.input_file, output_file, q, p, target_fps)

            self.root.after(0, self.finish, "Готово! Результат сохранен", "green")
        except Exception as e:
            print(f"Error during processing: {e}")
            self.root.after(0, self.finish, f"Ошибка! {str(e)[:30]}...", "red")

    def finish(self, msg, color):
        self.lbl_status.config(text=msg, foreground=color)
        self.btn_start.config(state="normal")
        if color == "green":
            messagebox.showinfo("Успех", msg)

    def process_video_accurate(self, input_path, output_path, q, p, target_fps):
        clip = VideoFileClip(input_path)
        # Process each frame via PIL
        shakal_clip = clip.fl_image(lambda f: np.array(self._shakalize_pil_image(Image.fromarray(f), q, p)))
        
        temp_v = "temp_v.mp4"
        shakal_clip.write_videofile(temp_v, fps=target_fps, codec="libx264", audio=False, logger=None)
        
        self._add_bad_audio(temp_v, input_path, output_path, q)
        if os.path.exists(temp_v): 
            os.remove(temp_v)
        clip.close()

    def process_video_fast(self, input_path, output_path, q, p, target_fps):
        ffmpeg_exe = get_ffmpeg_exe()
        v_bitrate = f"{max(2, 500 - q*5)}k"
        
        vf = f"fps={target_fps},scale=iw/{p}:-1,scale=iw*{p}:-1:flags=neighbor"
        if q > 50:
            vf += f",noise=alls={int(q/4)}:allf=t"

        cmd =[
            ffmpeg_exe, "-y", "-i", input_path,
            "-vf", vf,
            "-b:v", v_bitrate, "-maxrate", v_bitrate, "-bufsize", "50k",
            "-c:a", "aac", "-ar", "8000", "-b:a", f"{max(8, 64-q)}k",
            output_path
        ]
        
        # Suppress ffmpeg output in console
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)

    def _add_bad_audio(self, video_v, original_media, output_p, q):
        ffmpeg_exe = get_ffmpeg_exe()
        rates =[44100, 22050, 11025, 8000]
        idx = min(len(rates)-1, int(q/30))
        ar = rates[idx]
        ab = f"{max(8, 128-q)}k"

        cmd =[
            ffmpeg_exe, "-y", "-i", video_v, "-i", original_media,
            "-map", "0:v", "-map", "1:a?", "-c:v", "copy",
            "-c:a", "aac", "-ar", str(ar), "-b:a", ab, output_p
        ]
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)

if __name__ == "__main__":
    root = tk.Tk()
    app = ShakalizerApp(root)
    root.mainloop()