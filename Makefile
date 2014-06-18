CXXFLAGS := `sdl2-config --cflags` -Iinclude -I. -Ilibs/SDL2_ttf-2.0.12
CXXFLAGS += -Wall -pipe -g --pedantic
CXXFLAGS += --std=c++11

LIBS += `sdl2-config --libs`
LIBS += -lSDL2_image
LIBS += -lSDL2_mixer
LIBS += libs/SDL2_ttf-2.0.12/.libs/libSDL2_ttf.a -lfreetype

LDFLAGS += -Wall
LDFLAGS += --std=c++11

OUTPUT := programa.out

OBJDIR := obj
SRCDIR := src

SRCS := $(notdir $(shell ls -t $(SRCDIR)/*.cpp))

OBJS := $(addprefix $(OBJDIR)/, $(addsuffix .o,$(basename $(SRCS))))


all: $(OUTPUT)

$(OBJDIR)/%.o: $(SRCDIR)/%.cpp
	@echo "Compiling..." $(notdir $<)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(OUTPUT): $(OBJS)
	@echo "Linking binary..."
	$(CXX) $(LDFLAGS) -o $@ $^ $(LIBS)
	@echo "Done."

clean:
	rm $(OBJS) $(OUTPUT) *~ -rf
