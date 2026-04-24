import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from PIL import Image, ImageEnhance
import io
import os
import threading
import numpy as np
from moviepy import VideoFileClip
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
        self.root.geometry("480x520") # Уменьшил высоту, так как убрали блок выбора режима
        self.root.resizable(False, False)

        self.input_file = None
        self.output_file = None 
        self.original_fps = 30

        self._build_ui()

    def _build_ui(self):
        # --- UI Elements ---
        self.btn_select = ttk.Button(self.root, text="1. Выбрать исходный файл", command=self.select_file)
        self.btn_select.pack(pady=(10, 0))

        self.lbl_file = ttk.Label(self.root, text="Файл не выбран", foreground="gray")
        self.lbl_file.pack(pady=(0, 10))

        # Кнопка сохранения
        self.btn_save_as = ttk.Button(self.root, text="2. Куда сохранить результат?", command=self.select_output_path, state="disabled")
        self.btn_save_as.pack(pady=(0, 0))

        self.lbl_save = ttk.Label(self.root, text="Путь не выбран", foreground="gray")
        self.lbl_save.pack(pady=(0, 10))

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

        # Start Button
        self.btn_start = ttk.Button(self.root, text="УШАТАТЬ В ХЛАМ", command=self.start_processing, state="disabled")
        self.btn_start.pack(pady=20)

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
            
            if ext in ['mp4', 'avi', 'mov', 'mkv']:
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
            self.btn_save_as.config(state="normal")
            
            base, ext_orig = os.path.splitext(filepath)
            default_ext = ".mp4" if ext in ['mp4', 'avi', 'mov', 'mkv'] else ext_orig
            self.output_file = f"{base}_shakal{default_ext}"
            self.lbl_save.config(text=os.path.basename(self.output_file), foreground="black")
            self.btn_start.config(state="normal")

    def select_output_path(self):
        if not self.input_file:
            return

        ext = self.input_file.split('.')[-1].lower()
        if ext in ['mp4', 'avi', 'mov', 'mkv']:
            filetypes = [("Video", "*.mp4")]
            def_ext = ".mp4"
        else:
            filetypes = [("Image", f"*.{ext}")]
            def_ext = f".{ext}"

        initial_dir = os.path.dirname(self.input_file)
        initial_name = os.path.basename(self.output_file)

        path = filedialog.asksaveasfilename(
            title="Сохранить как...",
            initialdir=initial_dir,
            initialfile=initial_name,
            defaultextension=def_ext,
            filetypes=filetypes
        )

        if path:
            self.output_file = path
            self.lbl_save.config(text=os.path.basename(path), foreground="black")

    def start_processing(self):
        if not self.input_file or not self.output_file:
            messagebox.showwarning("Внимание", "Выбери файл и место сохранения!")
            return
            
        self.btn_start.config(state="disabled")
        self.lbl_status.config(text="В процессе обработки...", foreground="blue")
        threading.Thread(target=self.process_file, daemon=True).start()

    def _shakalize_pil_image(self, img, quality, pixel_size):
        if img.mode != 'RGB':
            img = img.convert('RGB')
        
        w, h = img.size
        small_w = max(1, w // pixel_size)
        small_h = max(1, h // pixel_size)
        
        img = img.resize((small_w, small_h), Image.Resampling.BOX)
        
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
        
        try:
            if ext in ['png', 'jpg', 'jpeg']:
                img = Image.open(self.input_file)
                self._shakalize_pil_image(img, q, p).save(self.output_file)
            else:
                # Всегда используем точный режим
                self.process_video_accurate(self.input_file, self.output_file, q, p, target_fps)

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
        shakal_clip = clip.image_transform(lambda f: np.array(self._shakalize_pil_image(Image.fromarray(f), q, p)))
        
        temp_v = "temp_v.mp4"
        # Сохраняем временное видео без звука
        shakal_clip.write_videofile(temp_v, fps=target_fps, codec="libx264", audio=False, logger=None)
        
        # Накладываем плохой звук
        self._add_bad_audio(temp_v, input_path, output_path, q)
        
        if os.path.exists(temp_v): 
            os.remove(temp_v)
        clip.close()

    def _add_bad_audio(self, video_v, original_media, output_p, q):
        ffmpeg_exe = get_ffmpeg_exe()
        rates = [44100, 22050, 11025, 8000]
        idx = min(len(rates)-1, int(q/30))
        ar = rates[idx]
        ab = f"{max(8, 128-q)}k"

        cmd = [
            ffmpeg_exe, "-y", "-i", video_v, "-i", original_media,
            "-map", "0:v", "-map", "1:a?", "-c:v", "copy",
            "-c:a", "aac", "-ar", str(ar), "-b:a", ab, output_p
        ]
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)

if __name__ == "__main__":
    root = tk.Tk()
    app = ShakalizerApp(root)
    root.mainloop()
